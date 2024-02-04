#!/bin/bash

#########################################################################################################
# This script warps ROIs to TVDE and CALIPR space. 
# Then it creates CSV files for each metric in a new stats/ folder. Each metric file will have
# each row representing an ROI (in the order shown below). Mean and std are stored.
#########################################################################################################

##Use these flags to specify full path and subject ID.
while getopts p:s: flag 
do
    case "${flag}" in
        p) path=${OPTARG};;
        s) subject=${OPTARG};;
    esac 
done

echo ${subject}
echo ${path}
script_folder=$(cd -P -- "$(dirname -- "$0")" && pwd -P)


#Set up folder locations
#Make these folders as needed.
folder_base="${path}"
folder_mdd_base="${path}/${subject}/MDD"
folder_mdd="${path}/${subject}/MDD/processed"
folder_mdd_in="${path}/${subject}/MDD/Inputs"
folder_mwf="${path}/${subject}/CALIPR"
folder_ants="${path}/${subject}/ants"
folder_rois="${path}/${subject}/ants/ROIs"
folder_nifti="${path}/${subject}/NIFTI"
folder_parrec="${path}/${subject}/PARREC"


##########################Now let's do ANTs things.######################
#Extract brain. This takes a little time. Make the directory for it first.
echo "3DT1 brain extraction"
cd ${script_folder}
mkdir ${folder_ants}/3DT1
antsBrainExtraction.sh -d 3 -a ${folder_nifti}/3DT1.nii.gz -e ../NKI_Template/T_template.nii.gz -m ../NKI_Template/T_template_BrainCerebellumProbabilityMask.nii.gz -o ${folder_ants}/3DT1/

##########3DT1 to MNI
#Let's try registering the T1 to the MNI 1mm template (which lives in this folder as well).
#The warped T1 template is in Warped.nii.gz, view BrainExtractionBrain and Warped together to see that they fit.
##The warp to use forever on is 0GenericAffine.mat
echo "Registering 3DT1 to MNI template"
mv ${folder_ants}/3DT1/BrainExtractionBrain.nii.gz ${folder_ants}/3DT1/3DT1.nii.gz 
antsRegistrationSyNQuick.sh -d 3 -f ${folder_ants}/3DT1/3DT1.nii.gz -m MNI152_T1_1mm_brain.nii.gz -o ${folder_ants}/3DT1/ -n 6

##########MDD setting up stuff
#Make directories to store MDD data in ants folder
echo "Setting up MDD ANTs folder"
mkdir ${folder_ants}/MDD
fslroi ${folder_mdd}/FWF_mc.nii.gz ${folder_ants}/MDD/FWF_mc_b0.nii.gz 0 1
fslmaths ${folder_ants}/MDD/FWF_mc_b0.nii.gz -mul ${folder_mdd_in}/mask.nii.gz ${folder_ants}/MDD/FWF_mc_b0.nii.gz

######################Register everything to 3DT1, ie CALIPR->3DT1, MDD->3DT1, DTI->3DT1#######
echo "Registering TVDE and CALIPR to 3DT1"
mkdir ${folder_ants}/MDD_3DT1
antsRegistrationSyN.sh -d 3 -f ${folder_ants}/MDD/FWF_mc_b0.nii.gz -m ${folder_ants}/3DT1/3DT1.nii.gz -r 1 -g 0.05 -o ${folder_ants}/MDD_3DT1/

mkdir ${folder_ants}/CALIPR_3DT1
antsRegistrationSyN.sh -d 3 -f ${folder_ants}/CALIPR/${subject}_E1.nii.gz -m ${folder_ants}/3DT1/3DT1.nii.gz -o ${folder_ants}/CALIPR_3DT1/ -n 8 -t s

#Also register CALIPR->MDD for tract profiling. This seems to be the most finicky, there were some special cases that needed slightly different parameters.
echo "Registering TVDE and CALIPR"
mkdir ${folder_ants}/CALIPR_MDD
antsRegistrationSyN.sh -d 3 -m ${folder_ants}/CALIPR/${subject}_E28.nii.gz -f ${folder_ants}/MDD/FWF_mc_b0.nii.gz -o ${folder_ants}/CALIPR_MDD/ -t a -r 5
echo "Warping MWF to TVDE space"
antsApplyTransforms -d 3 -e 0 -i ${folder_ants}/CALIPR/MWF_brain.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/CALIPR_MDD/0GenericAffine.mat -o ${folder_ants}/CALIPR_MDD/MWF.nii.gz


# ####################Concatenate warps to go from MNI T1->MDD, MNIT1->CALIPR for ROI analysis#######
echo "Concatenating warps to MNI space"
antsApplyTransforms -d 3 -o [${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz,1] -t ${folder_ants}/CALIPR_3DT1/1Warp.nii.gz -t ${folder_ants}/CALIPR_3DT1/0GenericAffine.mat -t ${folder_ants}/3DT1/1Warp.nii.gz -t ${folder_ants}/3DT1/0GenericAffine.mat -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -v
antsApplyTransforms -d 3 -i ${script_folder}/MNI152_T1_1mm_brain.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -o ${folder_ants}/CALIPR/concatenated_mnitocalipr_warped.nii.gz -v

antsApplyTransforms -d 3 -o [${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz,1] -t ${folder_ants}/MDD_3DT1/1Warp.nii.gz -t ${folder_ants}/MDD_3DT1/0GenericAffine.mat -t ${folder_ants}/3DT1/1Warp.nii.gz -t ${folder_ants}/3DT1/0GenericAffine.mat -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -v
antsApplyTransforms -d 3 -i ${script_folder}/MNI152_T1_1mm_brain.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -o ${folder_ants}/MDD/concatenated_mnitomdd_warped.nii.gz -v

#################And now warp ROIs to CALIPR and MDD space to get ROI values from these eventually##########
echo "Warping ROIs from MNI space to CALIPR space"

folder_base_rois="../ROIs"
mkdir ${folder_rois}
#Make a folder to store ROI bits in CALIPR space
mkdir ${folder_rois}/CALIPR

#Warp the 13 bits to CALIPR space. ROIs are in MNI space to begin with.
#CC
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/genu_CC.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/genu_CC.nii.gz
fslmaths ${folder_rois}/CALIPR/genu_CC.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/genu_CC.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/body_CC.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/body_CC.nii.gz
fslmaths ${folder_rois}/CALIPR/body_CC.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/body_CC.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/splenium_CC.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/splenium_CC.nii.gz
fslmaths ${folder_rois}/CALIPR/splenium_CC.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/splenium_CC.nii.gz

#Other WM structures
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/ATR.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/ATR.nii.gz
fslmaths ${folder_rois}/CALIPR/ATR.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/ATR.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/CING.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/CING.nii.gz
fslmaths ${folder_rois}/CALIPR/CING.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/CING.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/CST.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/CST.nii.gz
fslmaths ${folder_rois}/CALIPR/CST.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/CST.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/For_Min.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/For_Min.nii.gz
fslmaths ${folder_rois}/CALIPR/For_Min.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/For_Min.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/For_Maj.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/For_Maj.nii.gz
fslmaths ${folder_rois}/CALIPR/For_Maj.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/For_Maj.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/SLF.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/SLF.nii.gz
fslmaths ${folder_rois}/CALIPR/SLF.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/SLF.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/ILF.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/ILF.nii.gz
fslmaths ${folder_rois}/CALIPR/ILF.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/ILF.nii.gz

#GM structures
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/thalamus.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/thalamus.nii.gz
fslmaths ${folder_rois}/CALIPR/thalamus.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/thalamus.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/caudate.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/caudate.nii.gz
fslmaths ${folder_rois}/CALIPR/caudate.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/caudate.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/putamen.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR/concatenated_mnitocalipr_warp.nii.gz -o ${folder_rois}/CALIPR/putamen.nii.gz
fslmaths ${folder_rois}/CALIPR/putamen.nii.gz -thr 0.95 -bin ${folder_rois}/CALIPR/putamen.nii.gz


#Make a folder to store ROI bits in MDD space
echo "Warping ROIs from MNI space to TVDE space"
mkdir ${folder_rois}/MDD

#Warp the 13 bits to MDD space. Start from the ROIs in MNI space.
#CC
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/genu_CC.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/genu_CC.nii.gz
fslmaths ${folder_rois}/MDD/genu_CC.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/genu_CC.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/body_CC.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/body_CC.nii.gz
fslmaths ${folder_rois}/MDD/body_CC.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/body_CC.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/splenium_CC.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/splenium_CC.nii.gz
fslmaths ${folder_rois}/MDD/splenium_CC.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/splenium_CC.nii.gz

#Other WM structures
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/ATR.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/ATR.nii.gz
fslmaths ${folder_rois}/MDD/ATR.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/ATR.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/CING.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/CING.nii.gz
fslmaths ${folder_rois}/MDD/CING.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/CING.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/CST.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/CST.nii.gz
fslmaths ${folder_rois}/MDD/CST.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/CST.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/For_Min.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/For_Min.nii.gz
fslmaths ${folder_rois}/MDD/For_Min.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/For_Min.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/For_Maj.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/For_Maj.nii.gz
fslmaths ${folder_rois}/MDD/For_Maj.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/For_Maj.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/SLF.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/SLF.nii.gz
fslmaths ${folder_rois}/MDD/SLF.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/SLF.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/ILF.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/ILF.nii.gz
fslmaths ${folder_rois}/MDD/ILF.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/ILF.nii.gz

#GM structures
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/thalamus.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/thalamus.nii.gz
fslmaths ${folder_rois}/MDD/thalamus.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/thalamus.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/caudate.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/caudate.nii.gz
fslmaths ${folder_rois}/MDD/caudate.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/caudate.nii.gz
antsApplyTransforms -d 3 -e 0 -i ${folder_base_rois}/putamen.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD/concatenated_mnitomdd_warp.nii.gz -o ${folder_rois}/MDD/putamen.nii.gz
fslmaths ${folder_rois}/MDD/putamen.nii.gz -thr 0.95 -bin ${folder_rois}/MDD/putamen.nii.gz

#############Make white matter masks###############
#Get a WM/GM/CSF mask in 3DT1 space. For one case, Otsu worked better than KMeans, so best to check.
Atropos -d 3 -a ${folder_ants}/3DT1/3DT1.nii.gz -i KMeans[3] -x ${folder_ants}/3DT1/BrainExtractionMask.nii.gz -o ${folder_ants}/3DT1/segmented.nii.gz

#Get just the WM out of this as a mask. "3" stands for WM.
fslmaths ${folder_ants}/3DT1/segmented.nii.gz -thr 3 -uthr 3 -bin ${folder_ants}/3DT1/wm_mask.nii.gz

#Also get out CSF mask to use when we do tract profiling (so we're sure we don't capture CSF).
fslmaths ${folder_ants}/3DT1/segmented.nii.gz -thr 1 -uthr 1 -bin ${folder_ants}/3DT1/csf_mask.nii.gz

#Warp WM mask to CALIPR space
antsApplyTransforms -d 3 -e 0 -i ${folder_ants}/3DT1/wm_mask.nii.gz -r ${folder_ants}/CALIPR/${subject}_E1.nii.gz -t ${folder_ants}/CALIPR_3DT1/1Warp.nii.gz -t ${folder_ants}/CALIPR_3DT1/0GenericAffine.mat -o ${folder_ants}/CALIPR/wm_mask.nii.gz
fslmaths ${folder_ants}/CALIPR/wm_mask.nii.gz -thr 0.9 -bin ${folder_ants}/CALIPR/wm_mask.nii.gz
cp ${folder_ants}/CALIPR/wm_mask.nii.gz ${folder_rois}/CALIPR/wm_mask.nii.gz

#Warp WM to TVDE space also
antsApplyTransforms -d 3 -e 0 -i ${folder_ants}/3DT1/wm_mask.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD_3DT1/1Warp.nii.gz -t ${folder_ants}/MDD_3DT1/0GenericAffine.mat -o ${folder_ants}/MDD/wm_mask.nii.gz
fslmaths ${folder_ants}/MDD/wm_mask.nii.gz -thr 0.9 -bin ${folder_ants}/MDD/wm_mask.nii.gz
cp ${folder_ants}/MDD/wm_mask.nii.gz ${folder_rois}/MDD/wm_mask.nii.gz

#Warp CSF to TVDE space for tract profiling purposes.
antsApplyTransforms -d 3 -e 0 -i ${folder_ants}/3DT1/csf_mask.nii.gz -r ${folder_ants}/MDD/FWF_mc_b0.nii.gz -t ${folder_ants}/MDD_3DT1/1Warp.nii.gz -t ${folder_ants}/MDD_3DT1/0GenericAffine.mat -o ${folder_ants}/MDD/csf_mask.nii.gz
fslmaths ${folder_ants}/MDD/csf_mask.nii.gz -thr 0.99 -bin ${folder_ants}/MDD/csf_mask.nii.gz
#Invert it so non-CSF is 1 and CSF is 0, for use in profiling.
fslmaths ${folder_ants}/MDD/csf_mask.nii.gz -mul -1 -add 1 ${folder_ants}/MDD/csf_mask.nii.gz


#####Now we deal with extracting metric values and storing them.
#These are the regions we will use for all metrics.
declare -a regions=("genu_CC" "body_CC" "splenium_CC" "ATR" "CING" "CST" "For_Min" "For_Maj" "SLF" "ILF" "wm_mask" "thalamus" "caudate" "putamen")

#These are metrics from different diffusion pipelines.
#From MDD we aim to get a voxel-level measure of size, shape and variance of size of diffusion tensors of micro-environments.
declare -a metric_mdd_maps=("qti/qti_ufa" "qti/qti_fa" "qti/qti_c_c" "qti/qti_md" "qti/qti_c_md") 


Create folders to hold CSV files of stats.
folder_mdd="${path}/${subject}/MDD/processed"
folder_mwf="${path}/${subject}/CALIPR"
folder_rois="${path}/${subject}/ants/ROIs"
folder_stats="${path}/${subject}/stats"
mkdir ${folder_stats} 
mkdir ${folder_stats}/qti
mkdir ${folder_stats}/mwi

for j in "${metric_mdd_maps[@]}"; do
echo "Mean Std" >> ${folder_stats}/${j}.csv
for i in "${regions[@]}"; do
echo ${i}
fslstats ${folder_mdd}/${j}.nii.gz -k ${folder_rois}/MDD/${i}.nii.gz -m -s>> ${folder_stats}/${j}.csv
done 
done

#And MWI metrics
declare -a metric_mwf_maps=("${subject}_CALIPR_MWF") 
mkdir ${folder_stats}/mwi
for j in "${metric_mwf_maps[@]}"; do
echo "Mean Std" >> ${folder_stats}/mwi/${j}.csv
for i in "${regions[@]}"; do
echo ${i}
fslstats ${folder_mwf}/${j}.nii.gz -k ${folder_rois}/CALIPR/${i}.nii.gz -m -s>> ${folder_stats}/mwi/${j}.csv
done 
done