#!/bin/bash 

##################################################################################################################
# This script generates z-score maps for a given subject, for all metrics of interest.
# This requires the metric atlases to already be made, and for the subject to have metric maps made as well.
# Also basic registrations (CALIPR and MDD to 3DT1) should be done.
# These subjects would not have their 3DT1s already registered to atlas space so that needs to be done too.
# Usage: ./zscore.sh -p path/to/folder/of/all_subject_folders -s subject_id
# Output: z-score maps of all metrics in the subject's folder.
##################################################################################################################

#Use these flags to specify full path to folder containing all data, and a file containing all subjects that should go into the tract atlas.
while getopts p:s: flag 
do
    case "${flag}" in
        p) path=${OPTARG};;
        s) subject=${OPTARG};;
    esac 
done

script_folder=$(cd -P -- "$(dirname -- "$0")" && pwd -P) #Keep track of where this actual file tractography_atlas.sh lives

echo ${subject}

#Set up folder locations
#Make these folders as needed.
folder_base="${path}"
folder_atlas="${path}/atlas"

cd ${folder_base} #Get into the base folder for the next few things

#Register the subject's 3DT1 to atlas space.
echo "Registering 3DT1 to atlas space"
antsRegistrationSyNQuick.sh -d 3 -m ${subject}/ants/3DT1/3DT1.nii.gz -f ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/3DT1/atlas_ -n 8 

#We should already have CALIPR to 3DT1. Chain together with 3DT1->template to create a CALIPR->template warp
echo "Registering CALIPR to atlas space"
antsApplyTransforms -d 3 -o [${subject}/ants/CALIPR/concatenated_caliprtoatlas_warp.nii.gz,1] -t ${subject}/ants/3DT1/atlas_1Warp.nii.gz -t ${subject}/ants/3DT1/atlas_0GenericAffine.mat -t ${subject}/ants/CALIPR_3DT1/1InverseWarp.nii.gz -t [${subject}/ants/CALIPR_3DT1/0GenericAffine.mat,1] -r ${folder_atlas}/template_3dt1.nii.gz -v
#Test it out on E1
antsApplyTransforms -d 3 -i ${subject}/ants/CALIPR/${subject}_E1.nii.gz -t ${subject}/ants/CALIPR/concatenated_caliprtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/CALIPR/e1_atlas_space.nii.gz -v

#We should already have MDD to 3DT1. Chain together with 3DT1->template to create a MDD->template warp
echo "Registering MDD to atlas space"
antsApplyTransforms -d 3 -o [${subject}/ants/MDD/concatenated_mddtoatlas_warp.nii.gz,1] -t ${subject}/ants/3DT1/atlas_1Warp.nii.gz -t ${subject}/ants/3DT1/atlas_0GenericAffine.mat -t ${subject}/ants/MDD_3DT1/1InverseWarp.nii.gz -t [${subject}/ants/MDD_3DT1/0GenericAffine.mat,1] -r ${folder_atlas}/template_3dt1.nii.gz -v
#Test it out on B0
antsApplyTransforms -d 3 -i ${subject}/ants/MDD/FWF_mc_b0.nii.gz -t ${subject}/ants/MDD/concatenated_mddtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/MDD/b0_atlas_space.nii.gz -v

#Apply it to metric maps
antsApplyTransforms -d 3 -i ${subject}/ants/CALIPR/MWF_brain.nii.gz -t ${subject}/ants/CALIPR/concatenated_caliprtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/CALIPR/mwf_atlas_space.nii.gz -v
antsApplyTransforms -d 3 -i ${subject}/MDD/processed/qti/qti_ufa.nii.gz -t ${subject}/ants/MDD/concatenated_mddtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/MDD/ufa_atlas_space.nii.gz -v
antsApplyTransforms -d 3 -i ${subject}/MDD/processed/qti/qti_fa.nii.gz -t ${subject}/ants/MDD/concatenated_mddtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/MDD/fa_atlas_space.nii.gz -v
antsApplyTransforms -d 3 -i ${subject}/MDD/processed/qti/qti_c_md.nii.gz -t ${subject}/ants/MDD/concatenated_mddtoatlas_warp.nii.gz -r ${folder_atlas}/template_3dt1.nii.gz -o ${subject}/ants/MDD/cmd_atlas_space.nii.gz -v


#And now that these are in metric space, generate z-score maps. Z-score = (map - mean)/(std)
mkdir ${subject}/zscore
fslmaths ${subject}/ants/CALIPR/mwf_atlas_space.nii.gz -sub ${folder_atlas}/mwf_atlas.nii.gz -div ${folder_atlas}/mwf_std_atlas.nii.gz ${subject}/zscore/mwf_zscore.nii.gz 
fslmaths ${subject}/ants/MDD/ufa_atlas_space.nii.gz -sub ${folder_atlas}/ufa_atlas.nii.gz -div ${folder_atlas}/ufa_std_atlas.nii.gz ${subject}/zscore/ufa_zscore.nii.gz
fslmaths ${subject}/ants/MDD/fa_atlas_space.nii.gz -sub ${folder_atlas}/fa_atlas.nii.gz -div ${folder_atlas}/fa_std_atlas.nii.gz ${subject}/zscore/fa_zscore.nii.gz
fslmaths ${subject}/ants/MDD/cmd_atlas_space.nii.gz -sub ${folder_atlas}/cmd_atlas.nii.gz -div ${folder_atlas}/cmd_std_atlas.nii.gz ${subject}/zscore/cmd_zscore.nii.gz


#We should mask out CSF, otherwise that looks extra confusing.
#Take the original 3DT1 segmentation. 1 is CSF. Separate that out, then threshold it to make an inverse-CSF mask. Warp to atlas space, multiply that with z-score maps!
fslmaths ${subject}/ants/3DT1/segmented.nii.gz -uthr 1 -thr 1 ${subject}/ants/3DT1/csf.nii.gz
fslmaths ${subject}/ants/3DT1/csf.nii.gz -mul -1 -add 1 ${subject}/ants/3DT1/csf_inv.nii.gz
antsApplyTransforms -d 3 -i ${subject}/ants/3DT1/csf_inv.nii.gz -r atlas/template_3dt1.nii.gz -t ${subject}/ants/3DT1/atlas_1Warp.nii.gz -t ${subject}/ants/3DT1/atlas_0GenericAffine.mat -o ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -v
fslmaths ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -thr 0.99 -bin ${subject}/ants/3DT1/atlas_csf_inv.nii.gz


#Multiplying CSF-inverse mask with existing masks to remove CSF regions, and multiplying by CoV masks to get regions that are generally similar between people.
#Also thresholding it so that we see only negative z-scores (for things except CMD/Kbulk- positive for that), and multiplying that by -1 so that we can view it 
#with nice sensible colour scales on FSLeyes (so essentially, a z-score of -2 would now look like +2).
#We want negative z-scores because those indicate regions of decreased anisotropy/MWF (and +ve z-scores indicate higher heterogeneity).
fslmaths ${subject}/zscore/mwf_zscore.nii.gz -uthr 0 -mul -1 -mul ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -mul ${folder_atlas}/mwf_cov_mask.nii.gz ${subject}/zscore/mwf_zscore_thresh.nii.gz
fslmaths ${subject}/zscore/ufa_zscore.nii.gz -uthr 0 -mul -1 -mul ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -mul ${folder_atlas}/ufa_cov_mask.nii.gz ${subject}/zscore/ufa_zscore_thresh.nii.gz
fslmaths ${subject}/zscore/fa_zscore.nii.gz -uthr 0 -mul -1 -mul ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -mul ${folder_atlas}/fa_cov_mask.nii.gz ${subject}/zscore/fa_zscore_thresh.nii.gz
fslmaths ${subject}/zscore/cmd_zscore.nii.gz -thr 0 -mul 1 -mul ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -mul ${folder_atlas}/cmd_cov_mask.nii.gz ${subject}/zscore/cmd_zscore_thresh_upper.nii.gz
fslmaths ${subject}/zscore/cmd_zscore.nii.gz -uthr 0 -mul -1 -mul ${subject}/ants/3DT1/atlas_csf_inv.nii.gz -mul ${folder_atlas}/cmd_cov_mask.nii.gz ${subject}/zscore/cmd_zscore_thresh_lower.nii.gz

#Done! Now you can view the z-score maps overlaid on a 3DT1 in atlas space to see abnormalities. If FLAIR is present, warp that to atlas space and view.
echo "Z-score maps made"
