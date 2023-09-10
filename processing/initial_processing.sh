#!/bin/bash

#########################################################################################################
# This script creates metric maps from diffusion data and assumes MWF maps have already been generated.
# It registers ROIs to CALIPR and TVDE space to then extract metric means/stdevs.
# Usage: ./initial_processing.sh -p /full/path/to/main/datafolder -s subject_id
# Output: QTI+ metrics in MDD/processed/qti_degibbs; CALIPR 
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
script_folder=$(cd -P -- "$(dirname -- "$0")" && pwd -P) #The location of this actual script. 

#Set up folder locations
#Make these folders as needed.
folder_base="${path}"
folder_mdd_base="${path}/${subject}/MDD"
folder_mdd="${path}/${subject}/MDD/processed"
folder_mdd_in="${path}/${subject}/MDD/Inputs"
folder_mwf="${path}/${subject}/CALIPR"
folder_ants="${path}/${subject}/ants"
folder_rois="${path}/${subject}/ants/ROIs"
folder_base_rois="${script_folder}/ROIs"
folder_nifti="${path}/${subject}/NIFTI"
folder_parrec="${path}/${subject}/PARREC"


##First convert PARRECs to NIFTIs##########################
echo "Converting data to NIFTI"
mkdir ${folder_nifti}
dcm2niix -o ${folder_nifti} -f %p ${folder_parrec}
gzip ${folder_nifti}/*.nii 

##At this point, let's also fix the 3DT1s to overlay in a standard way with MNI (because it's a sagittal acquisition it looks weird)
echo "Fixing 3DT1 orientation"
fslreorient2std ${folder_nifti}/*T1*.nii.gz ${folder_nifti}/3DT1.nii.gz


#####################Doing MDD Processing#######################
#Next, copy MDD files into an MDD folder
mkdir ${folder_mdd_base}
mkdir ${folder_mdd_in}

#Move in the data into input folder for processing
echo "Copying in TVDE data"
cp ${folder_nifti}/*LTE*.* ${folder_mdd_in}/
cp ${folder_nifti}/*PTE*.* ${folder_mdd_in}/
cp ${folder_nifti}/*STE*.* ${folder_mdd_in}/
cp ${folder_nifti}/*MDD*.nii.gz ${folder_mdd_in}/Rev_B0.nii.gz

#####Now all the diffusion pre-processing. 
cd ${folder_base}

#Next, do topup for susceptibility correction on each type of encoding data
declare -a diffusion_type=("LTE" "PTE" "STE")
for encoding in "${diffusion_type[@]}"; do

    echo "Denoising and Degibbsing ${encoding}"
    #First denoise the data
    dwidenoise ${folder_mdd_in}/${encoding}.nii.gz ${folder_mdd_in}/${encoding}_processed1.nii.gz -noise ${folder_mdd_in}/${encoding}_noise.nii.gz -force
    #Then degibbs the data
    mrdegibbs ${folder_mdd_in}/${encoding}_processed1.nii.gz ${folder_mdd_in}/${encoding}_processed.nii.gz -force 
    #Some naming logistics to preserve the original data separately and call the denoised, degibbsed data the original name
    cp ${folder_mdd_in}/${encoding}.nii.gz ${folder_mdd_in}/${encoding}_og.nii.gz 
    cp ${folder_mdd_in}/${encoding}_processed.nii.gz ${folder_mdd_in}/${encoding}.nii.gz

    #Now topup for susceptibility correction
    echo "Topup with ${encoding} data"
    mkdir ${folder_mdd_in}/TOPUP_${encoding} 
    fslroi ${folder_mdd_in}/${encoding}.nii.gz ${folder_mdd_in}/TOPUP_${encoding}/b0.nii.gz 0 1

    ##Move acqparams.txt from here into the MDD folder (needed for topup)
    cp ${script_folder}/acqparams.txt ${folder_mdd_in}/TOPUP_${encoding}/acqparams.txt 
    cp ${folder_mdd_in}/Rev_B0.nii.gz ${folder_mdd_in}/TOPUP_${encoding}/rev_b0.nii.gz

    ##Now run topup 
    cd ${folder_mdd_in}/TOPUP_${encoding}
    fslmerge -t AP_PA b0 rev_b0
    topup --imain=AP_PA --datain=acqparams.txt --config=b02b0.cnf --out=my_topup --iout=my_topup_iout --fout=my_topup_fout
    fslmaths my_topup_iout.nii.gz -Tmean ${encoding}_b0_topup.nii.gz
    cd ${folder_base}
    applytopup --imain=${folder_mdd_in}/${encoding}.nii.gz --topup=${folder_mdd_in}/TOPUP_${encoding}/my_topup --inindex=1 --method=jac --interp=spline --out=${folder_mdd_in}/${encoding}_TOPUP --datain=${folder_mdd_in}/TOPUP_${encoding}/acqparams.txt --verbose

    ##And rename the TOPUP file back as LTE/STE/PTE for next steps.
    cp ${folder_mdd_in}/${encoding}_TOPUP.nii.gz ${folder_mdd_in}/${encoding}.nii.gz

done


#Brain extract the LTE image using dwi2mask since that seems to work best (way better than bet or ANTs). Use this as the mask for next steps.
dwi2mask ${folder_mdd_in}/LTE.nii.gz -fslgrad ${folder_mdd_in}/LTE.bvec ${folder_mdd_in}/LTE.bval -info -nthreads 8 ${folder_mdd_in}/mask.nii.gz

##Go back to the folder of this script
cd ${script_folder} 

#Now we need to do motion and eddy current correction. Using md-DMRI's ElastiX wrapper for that, and compile data into their format first.
matlab -nodisplay -nodesktop -nosplash -r "MDD_setup('${path}/', '${subject}');exit();"

#And run the actual QTI+ pipeline now for each subject to generate a bunch of metric maps.
matlab -nodisplay -nodesktop -nosplash -r "QTIPlus('${path}/', '${subject}');exit();"

#And fix the geometries/move into useful folder.
mkdir ${folder_mdd}/qti 
mv ${folder_mdd}/qti_* ${folder_mdd}/qti/


#Within QTI folder, copy geometry from other files and zip everything
gzip ${folder_mdd}/qti/qti_*.nii

fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_fa.nii.gz 
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_md.nii.gz 
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_rd.nii.gz 
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_ad.nii.gz 

fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_ufa.nii.gz 
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_c_c.nii.gz
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_c_mu.nii.gz
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_c_md.nii.gz 

fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_op.nii.gz
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_mk.nii.gz  
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_kbulk.nii.gz
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_kshear.nii.gz
fslcpgeom ${folder_mdd_in}/mask.nii.gz ${folder_mdd}/qti/qti_kmu.nii.gz


#Now deal with MWF####################################
####This assumes CALIPR with images already made into 56 volume set, MWF maps are made,
##brain is extracted, and all of it is in CALIPR folder#####
echo "Working on MWF logistics"
cd ${script_folder}
mkdir ${folder_ants}
mkdir ${folder_ants}/CALIPR

#Take 1st echo for registration to 3DT1, 28th echo for registration to TVDE
fslroi ${folder_mwf}/${subject}_CALIPR.nii.gz ${folder_ants}/CALIPR/${subject}_E1.nii.gz 0 1
fslroi ${folder_mwf}/${subject}_CALIPR.nii.gz ${folder_ants}/CALIPR/${subject}_E28.nii.gz 27 1
cp ${folder_mwf}/${subject}_BrainExtractionMask.nii.gz ${folder_ants}/CALIPR/BrainExtractionMask.nii.gz

#Multiply MWF map, E1, E28 by brain mask
fslmaths ${folder_mwf}/${subject}_CALIPR_MWF.nii.gz -mul ${folder_ants}/CALIPR/BrainExtractionMask.nii.gz ${folder_ants}/CALIPR/MWF_brain.nii.gz
fslmaths ${folder_ants}/CALIPR/${subject}_E28.nii.gz -mul ${folder_ants}/CALIPR/BrainExtractionMask.nii.gz ${folder_ants}/CALIPR/${subject}_E28.nii.gz
fslmaths ${folder_ants}/CALIPR/${subject}_E1.nii.gz -mul ${folder_ants}/CALIPR/BrainExtractionMask.nii.gz ${folder_ants}/CALIPR/${subject}_E1.nii.gz
#There! Now we have 56-echo MWF and related maps with clean backgrounds and extracted brains!! Good to go for next steps.
