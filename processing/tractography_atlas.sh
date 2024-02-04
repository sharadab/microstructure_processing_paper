#!/bin/bash

##################################################################################################################
# This script generates an FOD template using all the healthy subjects, and separate tracts in that template space.
# This requires pre-processed LTE data (denoised, degibbsed, susceptiblity corrected) in the MDD/Inputs/ folder.
# The FOD template and generated template-space tracts will all live in group_tractography, a new folder.
# Mostly following https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html?highlight=population%20template 
# Used commands from https://github.com/MIC-DKFZ/TractSeg/blob/master/resources/Tractometry_documentation.md with a fix from
# https://github.com/MIC-DKFZ/TractSeg/issues/154.
# Usage: ./tractography_atlas.sh -p path/to/folder/of/all_subject_folders -f filename_of_subject_list.txt
# Output: FOD template and tracts in template space, all in group_tractography. Also warps to go from template -> 1.25mm subject space in subject_folder/Tractography/
##################################################################################################################

#Use these flags to specify full path to folder containing all data, and a file containing all subjects that should go into the tract atlas.
while getopts p:f: flag 
do
    case "${flag}" in
        p) path=${OPTARG};;
        f) filename=${OPTARG};;
    esac 
done

#Inspiration: https://stackoverflow.com/questions/24628076/convert-multiline-string-to-array
some_data=$(<"$filename") #Read in the file
SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
IFS=$'\n'      # Change IFS to newline char
subject=($some_data) # split the `names` string into an array by the same name
IFS=$SAVEIFS   # Restore original IFS
for (( i=0; i<${#subject[@]}; i++ )) #As a sanity check, just print out all the subjects. It should be an array.
do
    echo "$i: ${subject[$i]}"
done

script_folder=$(cd -P -- "$(dirname -- "$0")" && pwd -P) #Keep track of where this actual file tractography_atlas.sh lives

#Set up folder locations
#Make these folders as needed.
folder_base="${path}"
folder_group_tractography="${path}/group_tractography"
folder_group_fod="${folder_group_tractography}/fod_input"
folder_group_mask="${folder_group_tractography}/mask_input"
tract="Tractography" #Just to conveniently use that folder 

mkdir ${folder_group_tractography}
mkdir ${folder_group_fod}
mkdir ${folder_group_mask}

cd ${folder_base} #Get into the base folder for the next few things

#Make a new folder in each subject for tractography stuff
for i in "${subject[@]}"; do
#In each subject's folder, make a tractography folder and copy in MDD's LTE data.
mkdir ${i}/Tractography
cp ${i}/MDD/Inputs/LTE.nii.gz ${i}/${tract}/${i}_LTE.nii.gz 
cp ${i}/MDD/Inputs/LTE.bval ${i}/${tract}/${i}_LTE.bval 
cp ${i}/MDD/Inputs/LTE.bvec ${i}/${tract}/${i}_LTE.bvec 

#Create response functions for 3 tissue types to further do MSMT-CSD
dwi2response dhollander ${i}/${tract}/${i}_LTE.nii.gz ${i}/${tract}/response_wm.txt ${i}/${tract}/response_gm.txt ${i}/${tract}/response_csf.txt -fslgrad ${i}/${tract}/${i}_LTE.bvec ${i}/${tract}/${i}_LTE.bval -info -nthreads 8

#Upsample the LTE image to 1.25mm resolution
mrgrid ${i}/${tract}/${i}_LTE.nii.gz regrid -vox 1.25 ${i}/${tract}/${i}_LTE_upsampled.nii.gz

#Create a brain mask from upsampled version
dwi2mask ${i}/${tract}/${i}_LTE_upsampled.nii.gz -fslgrad ${i}/${tract}/${i}_LTE.bvec ${i}/${tract}/${i}_LTE.bval -info -nthreads 8 ${i}/${tract}/${i}_mask_upsampled.nii.gz
done

#Append /Tractography/response_.txt to each entry in the subjects list, then pass it to responsemean.
wm_folders=( "${subject[@]/%//Tractography/response_wm.txt}" ) 
gm_folders=( "${subject[@]/%//Tractography/response_gm.txt}" ) 
csf_folders=( "${subject[@]/%//Tractography/response_csf.txt}" ) 
#Next, average all those response functions and stick it in one file. This gets used in the next step.
responsemean ${wm_folders[@]} ${folder_group_tractography}/group_average_response_wm.txt
responsemean ${gm_folders[@]} ${folder_group_tractography}/group_average_response_gm.txt
responsemean ${csf_folders[@]} ${folder_group_tractography}/group_average_response_csf.txt

#Next steps for each subject
for i in "${subject[@]}"; do
#Get FOD estimate using average response function
dwi2fod msmt_csd ${i}/${tract}/${i}_LTE_upsampled.nii.gz -fslgrad ${i}/${tract}/${i}_LTE.bvec ${i}/${tract}/${i}_LTE.bval ${folder_group_tractography}group_average_response_wm.txt ${i}/${tract}/wmfod.nii.gz ${folder_group_tractography}group_average_response_csf.txt ${i}/${tract}/gm.nii.gz  ${folder_group_tractography}group_average_response_csf.txt ${i}/${tract}/csf.nii.gz -mask ${i}/${tract}/${i}_mask_upsampled.nii.gz -force

##Joint bias field correction and intensity normalization. Based on https://community.mrtrix.org/t/error-using-mtnormalise/1111/4 I removed GM from this normalization because that was causing non-positive errors
##I guess because the GM FODs were ~0 or -ve? I guess its to do with voxel size/partial voluming so that 2 tissue works better than 3.
mtnormalise ${i}/${tract}/wmfod.nii.gz ${i}/${tract}/wmfod_norm.nii.gz ${i}/${tract}/csf.nii.gz ${i}/${tract}/csf_norm.nii.gz -mask ${i}/${tract}/${i}_mask_upsampled.nii.gz -force

#Symbolic link FOD images and masks into input folders
ln -s ${folder_base}/${i}/${tract}/wmfod_norm.nii.gz ${folder_base}/${folder_group_fod}/${i}_PRE.nii.gz 
ln -s ${folder_base}/${i}/${tract}/${i}_mask_upsampled.nii.gz ${folder_base}/${folder_group_mask}/${i}_PRE.nii.gz 

done

#This step took about 2.5 hours for 6, 4 hours for 12! Create a template from all the people's WM FODs. Using 10 cores (M1).
population_template ${folder_group_fod} -mask_dir ${folder_group_mask} ${folder_group_tractography}/wmfod_template.nii.gz -voxel_size 1.25 -nthreads 10

#Make each subject's mask be in template space now to create a template mask
for i in "${subject[@]}"; do
##Register subject FOD images to FOD template
mrregister ${i}/${tract}/wmfod_norm.nii.gz -mask1 ${i}/${tract}/${i}_mask_upsampled.nii.gz ${folder_group_tractography}/wmfod_template.nii.gz -nl_warp ${i}/${tract}/subject2template_warp.nii.gz ${i}/${tract}/template2subject_warp.nii.gz -force
##Transform masks into template space
mrtransform ${i}/${tract}/${i}_mask_upsampled.nii.gz -warp ${i}/${tract}/subject2template_warp.nii.gz -interp nearest -datatype bit ${i}/${tract}/mask_upsampled_template_space.nii.gz -force
done

##Put all the template space masks together to create a mask with maximum overlap. Check it!
mask_folders=( "${subject[@]/%//Tractography/mask_upsampled_template_space.nii.gz}" ) 
mrmath ${mask_folders[@]} min ${folder_group_tractography}/template_mask.nii.gz -datatype bit

##Segment out tracts (can use as seed points)
##First convert the WM FOD template to peaks (still in template space) to be able to use with TractSeg
sh2peaks -mask ${folder_group_tractography}/template_mask.nii.gz ${folder_group_tractography}/wmfod_template.nii.gz ${folder_group_tractography}/peaks_template.nii.gz
TractSeg -i ${folder_group_tractography}/peaks_template.nii.gz -o ${folder_group_tractography}/tractseg_output --output_type tract_segmentation

#Create startpoints and endpoints (to use for tracking)
TractSeg -i ${folder_group_tractography}/peaks_template.nii.gz -o ${folder_group_tractography}/tractseg_output --output_type endings_segmentation

#Create tract orientation maps to do tracking of segments
TractSeg -i ${folder_group_tractography}/peaks_template.nii.gz -o ${folder_group_tractography}/tractseg_output --output_type TOM

##If Tracking does work, run:
#Tracking -i peaks_template.nii.gz -o tractseg_output --tracking_format tck --algorithm prob --nr_fibers 5000

#Alternatively, use tckgen-- this generates a bundle for one tract. This is because TractSeg's Tracking had trouble, and I used a fix from: https://github.com/MIC-DKFZ/TractSeg/issues/154
cd ${folder_group_tractography}/
mkdir tractseg_output/tracking/ 
tckgen -algorithm FACT tractseg_output/TOM/CST_left.nii.gz tractseg_output/tracking/CST_left.tck -seed_image tractseg_output/bundle_segmentations/CST_left.nii.gz -include tractseg_output/endings_segmentations/CST_left_e.nii.gz -include tractseg_output/endings_segmentations/CST_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CST_right.nii.gz tractseg_output/tracking/CST_right.tck -seed_image tractseg_output/bundle_segmentations/CST_right.nii.gz -include tractseg_output/endings_segmentations/CST_right_e.nii.gz -include tractseg_output/endings_segmentations/CST_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_1.nii.gz tractseg_output/tracking/CC_1.tck -seed_image tractseg_output/bundle_segmentations/CC_1.nii.gz -include tractseg_output/endings_segmentations/CC_1_e.nii.gz -include tractseg_output/endings_segmentations/CC_1_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_2.nii.gz tractseg_output/tracking/CC_2.tck -seed_image tractseg_output/bundle_segmentations/CC_2.nii.gz -include tractseg_output/endings_segmentations/CC_2_e.nii.gz -include tractseg_output/endings_segmentations/CC_2_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_3.nii.gz tractseg_output/tracking/CC_3.tck -seed_image tractseg_output/bundle_segmentations/CC_3.nii.gz -include tractseg_output/endings_segmentations/CC_3_e.nii.gz -include tractseg_output/endings_segmentations/CC_3_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_4.nii.gz tractseg_output/tracking/CC_4.tck -seed_image tractseg_output/bundle_segmentations/CC_4.nii.gz -include tractseg_output/endings_segmentations/CC_4_e.nii.gz -include tractseg_output/endings_segmentations/CC_4_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_5.nii.gz tractseg_output/tracking/CC_5.tck -seed_image tractseg_output/bundle_segmentations/CC_5.nii.gz -include tractseg_output/endings_segmentations/CC_5_e.nii.gz -include tractseg_output/endings_segmentations/CC_5_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_6.nii.gz tractseg_output/tracking/CC_6.tck -seed_image tractseg_output/bundle_segmentations/CC_6.nii.gz -include tractseg_output/endings_segmentations/CC_6_e.nii.gz -include tractseg_output/endings_segmentations/CC_6_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC_7.nii.gz tractseg_output/tracking/CC_7.tck -seed_image tractseg_output/bundle_segmentations/CC_7.nii.gz -include tractseg_output/endings_segmentations/CC_7_e.nii.gz -include tractseg_output/endings_segmentations/CC_7_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CC.nii.gz tractseg_output/tracking/CC.tck -seed_image tractseg_output/bundle_segmentations/CC.nii.gz -include tractseg_output/endings_segmentations/CC_e.nii.gz -include tractseg_output/endings_segmentations/CC_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/AF_left.nii.gz tractseg_output/tracking/AF_left.tck -seed_image tractseg_output/bundle_segmentations/AF_left.nii.gz -include tractseg_output/endings_segmentations/AF_left_e.nii.gz -include tractseg_output/endings_segmentations/AF_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/AF_right.nii.gz tractseg_output/tracking/AF_right.tck -seed_image tractseg_output/bundle_segmentations/AF_right.nii.gz -include tractseg_output/endings_segmentations/AF_right_e.nii.gz -include tractseg_output/endings_segmentations/AF_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/ATR_left.nii.gz tractseg_output/tracking/ATR_left.tck -seed_image tractseg_output/bundle_segmentations/ATR_left.nii.gz -include tractseg_output/endings_segmentations/ATR_left_e.nii.gz -include tractseg_output/endings_segmentations/ATR_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/ATR_right.nii.gz tractseg_output/tracking/ATR_right.tck -seed_image tractseg_output/bundle_segmentations/ATR_right.nii.gz -include tractseg_output/endings_segmentations/ATR_right_e.nii.gz -include tractseg_output/endings_segmentations/ATR_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CG_left.nii.gz tractseg_output/tracking/CG_left.tck -seed_image tractseg_output/bundle_segmentations/CG_left.nii.gz -include tractseg_output/endings_segmentations/CG_left_e.nii.gz -include tractseg_output/endings_segmentations/CG_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/CG_right.nii.gz tractseg_output/tracking/CG_right.tck -seed_image tractseg_output/bundle_segmentations/CG_right.nii.gz -include tractseg_output/endings_segmentations/CG_right_e.nii.gz -include tractseg_output/endings_segmentations/CG_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_I_left.nii.gz tractseg_output/tracking/SLF_I_left.tck -seed_image tractseg_output/bundle_segmentations/SLF_I_left.nii.gz -include tractseg_output/endings_segmentations/SLF_I_left_e.nii.gz -include tractseg_output/endings_segmentations/SLF_I_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_I_right.nii.gz tractseg_output/tracking/SLF_I_right.tck -seed_image tractseg_output/bundle_segmentations/SLF_I_right.nii.gz -include tractseg_output/endings_segmentations/SLF_I_right_e.nii.gz -include tractseg_output/endings_segmentations/SLF_I_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_II_left.nii.gz tractseg_output/tracking/SLF_II_left.tck -seed_image tractseg_output/bundle_segmentations/SLF_II_left.nii.gz -include tractseg_output/endings_segmentations/SLF_II_left_e.nii.gz -include tractseg_output/endings_segmentations/SLF_II_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_II_right.nii.gz tractseg_output/tracking/SLF_II_right.tck -seed_image tractseg_output/bundle_segmentations/SLF_II_right.nii.gz -include tractseg_output/endings_segmentations/SLF_II_right_e.nii.gz -include tractseg_output/endings_segmentations/SLF_II_right_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_III_left.nii.gz tractseg_output/tracking/SLF_III_left.tck -seed_image tractseg_output/bundle_segmentations/SLF_III_left.nii.gz -include tractseg_output/endings_segmentations/SLF_III_left_e.nii.gz -include tractseg_output/endings_segmentations/SLF_III_left_b.nii.gz -nthreads 6
tckgen -algorithm FACT tractseg_output/TOM/SLF_III_right.nii.gz tractseg_output/tracking/SLF_III_right.tck -seed_image tractseg_output/bundle_segmentations/SLF_III_right.nii.gz -include tractseg_output/endings_segmentations/SLF_III_right_e.nii.gz -include tractseg_output/endings_segmentations/SLF_III_right_b.nii.gz -nthreads 6

##And now we should have tracts generated in template space! 
