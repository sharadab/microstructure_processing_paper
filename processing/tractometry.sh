#!/bin/bash
##################################################################################################################
# This script performs tractometry on all subjects specified in tractography_subjects.txt (both healthy and pathology cases).
# This requires that all subjects have had all tractography processing done and have warps generated to go from template space -> upsampled subject space.
# The template space tracts live in group_tractography/tractseg_output/tracking/
# Used commands from https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/Tractometry_documentation.md
# Usage: ./tractometry.sh -p path/to/folder/of/all_subject_folders -f filename_of_subject_list.txt
# Output: Tract profiling results for each metric, for all regions, in subject_folder/Tractography/tractseg_output/Tractometry.csv
##################################################################################################################

#Use these flags to specify full path to folder containing all data, and a file containing all subjects that should be processed.
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
tract="Tractography" #Just to conveniently use that folder 
mdd_processed="MDD/processed"
ants_mwf_mdd="ants/CALIPR_MDD"
ants_mdd="ants/MDD"
echo ${subject}

cd ${folder_base} #Get into the base folder for the next few things

#First, create a template volume to test registration with
fslroi ${folder_group_tractography}/peaks_template.nii.gz ${folder_group_tractography}/template_1volume.nii.gz 0 1
fslmaths ${folder_group_tractography}/template_1volume.nii.gz -nan ${folder_group_tractography}/template_1volume.nii.gz
fslroi ${folder_group_tractography}/wmfod_template.nii.gz ${folder_group_tractography}/wmfodtemplate_1volume.nii.gz 0 1

#Create warps to go from 3mm to atlas space. So far there should be a warp to from template -> 1.25mm subject space.
#Register subject B0 images to template (the original 3mm version) so that there is a way to transform tracts into subject space again.
First make B0 3mm image and B0 1.25mm image and register them
fslroi ${subject}/${tract}/${subject}_LTE.nii.gz ${subject}/${tract}/b0.nii.gz 0 1
fslroi ${subject}/${tract}/${subject}_LTE_upsampled.nii.gz ${subject}/${tract}/b0_upsampled.nii.gz 0 1
cp ${subject}/MDD/Inputs/mask.nii.gz ${subject}/${tract}/mask_3mm.nii.gz
fslmaths ${subject}/${tract}/b0.nii.gz -mul ${subject}/${tract}/mask_3mm.nii.gz ${subject}/${tract}/b0_masked.nii.gz

mrregister ${subject}/${tract}/b0_masked.nii.gz -mask1 ${subject}/${tract}/mask_3mm.nii.gz ${subject}/${tract}/b0_upsampled.nii.gz -mask2 ${subject}/${tract}/${subject}_mask_upsampled.nii.gz -nl_warp ${subject}/${tract}/downsampled_to_upsampled_warp.nii.gz ${subject}/${tract}/upsampled_to_downsampled_warp.nii.gz -force

transformcompose ${subject}/${tract}/template2subject_warp.nii.gz ${subject}/${tract}/upsampled_to_downsampled_warp.nii.gz ${subject}/${tract}/template_to_3mm_warp.nii.gz -template ${subject}/${tract}/b0_masked.nii.gz -force
transformcompose ${subject}/${tract}/downsampled_to_upsampled_warp.nii.gz ${subject}/${tract}/subject2template_warp.nii.gz ${subject}/${tract}/downsampled_to_template_warp.nii.gz -template group_tractography/template_1volume.nii.gz -force

#Apply warps and make sure they work!
mrtransform group_tractography/wmfodtemplate_1volume.nii.gz -warp ${subject}/${tract}/template_to_3mm_warp.nii.gz -interp nearest ${subject}/${tract}/template_to_subject_3mm.nii.gz -force
mrtransform ${subject}/${tract}/b0.nii.gz -warp ${subject}/${tract}/downsampled_to_template_warp.nii.gz -interp nearest ${subject}/${tract}/subject_to_template.nii.gz -force

#Transform files (endpoints and tracks) based on the transforms created above.
#Create some new folders first
mkdir ${subject}/${tract}/tractseg
mkdir ${subject}/${tract}/tractseg/endings_segmentations
mkdir ${subject}/${tract}/tractseg/tracking 
subject_tracks=${folder_base}/${subject}/${tract}/tractseg/tracking
subject_endpoints=${folder_base}/${subject}/${tract}/tractseg/endings_segmentations
subject_folder=${folder_base}/${subject}/${tract}

#Transform endpoints
cd ${folder_group_tractography}/tractseg_output/endings_segmentations 
for file in *; do
echo ${file}
mrtransform ${file} -warp ${subject_folder}/template_to_3mm_warp.nii.gz -interp linear ${subject_endpoints}/${file} -force
done

#Transform actual tracts
cd ${base_folder}
cd ${folder_group_tractography}/tractseg_output/tracking 
for file in *; do
echo ${file}
tcktransform ${file} ${subject_folder}/downsampled_to_template_warp.nii.gz ${subject_tracks}/${file}
done

#Go back to base folder
cd ${folder_base}

#Copy over metric maps in MDD space into the Tractography folder. Multiply all maps by CSF mask to remove CSF before tract profiling.
folder=${subject}/${tract}
fslmaths ${subject}/${mdd_processed}/qti/qti_fa.nii.gz -mul ${subject}/${ants_mdd}/csf_mask.nii.gz ${folder}/fa.nii.gz
fslmaths ${subject}/${mdd_processed}/qti/qti_ufa.nii.gz -mul ${subject}/${ants_mdd}/csf_mask.nii.gz ${folder}/ufa.nii.gz
fslmaths ${subject}/${mdd_processed}/qti/qti_c_md.nii.gz -mul ${subject}/${ants_mdd}/csf_mask.nii.gz ${folder}/cmd.nii.gz
fslmaths ${subject}/${mdd_processed}/qti/qti_c_c.nii.gz -mul ${subject}/${ants_mdd}/csf_mask.nii.gz ${folder}/cc.nii.gz
fslmaths ${subject}/${ants_mwf_mdd}/MWF.nii.gz -mul ${subject}/${ants_mdd}/csf_mask.nii.gz ${folder}/mwf.nii.gz

#And finally actually do the profiling
cd ${subject}/${tract}/tractseg
subject_folder=${folder_base}/${subject}/${tract}

Tractometry -i tracking/ -o Tractometry_fa.csv -e endings_segmentations/ -s ${subject_folder}/fa.nii.gz --tracking_format tck 
Tractometry -i tracking/ -o Tractometry_ufa.csv -e endings_segmentations/ -s ${subject_folder}/ufa.nii.gz --tracking_format tck 
Tractometry -i tracking/ -o Tractometry_cc.csv -e endings_segmentations/ -s ${subject_folder}/cc.nii.gz --tracking_format tck 
Tractometry -i tracking/ -o Tractometry_cmd.csv -e endings_segmentations/ -s ${subject_folder}/cmd.nii.gz --tracking_format tck 
Tractometry -i tracking/ -o Tractometry_mwf.csv -e endings_segmentations/ -s ${subject_folder}/mwf.nii.gz --tracking_format tck 

