#!/bin/bash

##################################################################################################################
# This script does all the tractography processing for subjects who are not part of the template creation (eg cases of pathology), takes one subject at a time.
# This requires pre-processed LTE data (denoised, degibbsed, susceptiblity corrected) in the MDD/Inputs/ folder.
# The FOD template and generated template-space tracts already exist and live in group_tractography.
# Mostly following https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html?highlight=population%20template 
# Used commands from https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/Tractometry_documentation.md with a fix from
# https://github.com/MIC-DKFZ/TractSeg/issues/154.
# Usage: ./tractography_special_subjects.sh -p path/to/folder/of/all_subject_folders -s subject_id
# Output: Warps to go from template -> 1.25mm subject space, in subject_folder/Tractography/
##################################################################################################################

#Use these flags to specify full path to folder containing all data, and a file containing all subjects that should be processed (not part of the group that forms the atlas).
while getopts p:s: flag 
do
    case "${flag}" in
        p) path=${OPTARG};;
        s) subject=${OPTARG};;
    esac 
done

script_folder=$(cd -P -- "$(dirname -- "$0")" && pwd -P) #Keep track of where this actual file tractography_atlas.sh lives

#Set up folder locations
#Make these folders as needed.
folder_base="${path}"
folder_group_tractography="${path}/group_tractography"
folder_group_fod="${folder_group_tractography}/fod_input"
folder_group_mask="${folder_group_tractography}/mask_input"
tract="Tractography" #Just to conveniently use that folder 

cd ${folder_base} #Get into the base folder for the next few things

#In each subject's folder, make a tractography folder and copy in MDD's LTE data.
mkdir ${subject}/Tractography
cp ${subject}/MDD/Inputs/LTE.nii.gz ${subject}/${tract}/${subject}_LTE.nii.gz 
cp ${subject}/MDD/Inputs/LTE.bval ${subject}/${tract}/${subject}_LTE.bval 
cp ${subject}/MDD/Inputs/LTE.bvec ${subject}/${tract}/${subject}_LTE.bvec 

##Create "response functions" for 3 tissue types to further do MSMT-CSD
dwi2response dhollander ${subject}/${tract}/${subject}_LTE.nii.gz ${subject}/${tract}/response_wm.txt ${subject}/${tract}/response_gm.txt ${subject}/${tract}/response_csf.txt -fslgrad ${subject}/${tract}/${subject}_LTE.bvec ${subject}/${tract}/${subject}_LTE.bval -info -nthreads 8

#Upsample the LTE image to 1.25mm resolution
mrgrid ${subject}/${tract}/${subject}_LTE.nii.gz regrid -vox 1.25 ${subject}/${tract}/${subject}_LTE_upsampled.nii.gz

#Create a brain mask from upsampled version
dwi2mask ${subject}/${tract}/${subject}_LTE_upsampled.nii.gz -fslgrad ${subject}/${tract}/${subject}_LTE.bvec ${subject}/${tract}/${subject}_LTE.bval -info -nthreads 8 ${subject}/${tract}/${subject}_mask_upsampled.nii.gz

#Get FOD estimate
dwi2fod msmt_csd ${subject}/${tract}/${subject}_LTE_upsampled.nii.gz -fslgrad ${subject}/${tract}/${subject}_LTE.bvec ${subject}/${tract}/${subject}_LTE.bval ${folder_group_tractography}/group_average_response_wm.txt ${subject}/${tract}/wmfod.nii.gz ${folder_group_tractography}/group_average_response_csf.txt ${subject}/${tract}/gm.nii.gz  ${folder_group_tractography}/group_average_response_csf.txt ${subject}/${tract}/csf.nii.gz -mask ${subject}/${tract}/${subject}_mask_upsampled.nii.gz -force

##Joint bias field correction and intensity normalization. Based on https://community.mrtrix.org/t/error-using-mtnormalise/1111/4 I removed GM from this normalization because that was causing non-positive errors
##I guess because the GM FODs were ~0 or -ve? I guess its to do with voxel size/partial voluming so that 2 tissue works better than 3.
mtnormalise ${subject}/${tract}/wmfod.nii.gz ${subject}/${tract}/wmfod_norm.nii.gz ${subject}/${tract}/csf.nii.gz ${subject}/${tract}/csf_norm.nii.gz -mask ${subject}/${tract}/${subject}_mask_upsampled.nii.gz -force

##Register subject FOD images to FOD template
mrregister ${subject}/${tract}/wmfod_norm.nii.gz -mask1 ${subject}/${tract}/${subject}_mask_upsampled.nii.gz ${folder_group_tractography}/wmfod_template.nii.gz -nl_warp ${subject}/${tract}/subject2template_warp.nii.gz ${subject}/${tract}/template2subject_warp.nii.gz -force

##Transform masks into template space
mrtransform ${subject}/${tract}/${subject}_mask_upsampled.nii.gz -warp ${subject}/${tract}/subject2template_warp.nii.gz -interp nearest -datatype bit ${subject}/${tract}/mask_upsampled_template_space.nii.gz -force


