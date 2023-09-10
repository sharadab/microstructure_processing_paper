#!/bin/bash

#################################################################################
## This shows an example pipeline on a set of sample data, starting with data in
## NIFTI format. Note that at the beginning, there are only 2 folders: CALIPR
## and PARREC. The CALIPR folder contains data that was already processed using 
## the pipeline in https://github.com/avdvorak/CALIPR which includes consolidating 
## 56 echoes of the T2 decay curve, creating a MWF map and brain extraction.
## The PARREC folder contains data in PAR/REC format.
#################################################################################

#List of subjects to process one by one
declare -a subjectlist=("SAMPLE")
#Folder where subjects will each have sub-folders
main_folder="/Users/sharada/Documents/GitHub/MWI_TVDE_Microstructure/example_usage"
#Folder where processing scripts live
script_folder="/Users/sharada/Documents/GitHub/MWI_TVDE_Microstructure/processing"



for subject in "${subjectlist[@]}"; do
##Make diffusion metric maps from QTI+, do some MWI logistics
bash ${script_folder}/initial_processing.sh -p ${main_folder} -s ${subject}

#Do registrations and extract ROI values of metrics.
#In the stats/ folder, the order in which metric values are placed is: genu, body, splenium, ATR, cingulum, CST, minor forceps, major forceps,SLF, ILF, WM mask, thalamus, caudate, putamen.
bash ${script_folder}/roi_analysis.sh -p ${main_folder} -s ${subject}

#We already have a study-specific tract atlas so process this individual subject to allow for tract profiling:
bash ${script_folder}/tractography_special_subjects.sh -p ${main_folder} -s ${subject}
#Now do the actual tract profiling. Note that all metric maps get CSF-masked for this step.
bash ${script_folder}/tractometry.sh -p ${main_folder} -s ${subject}

#We already have a study-specific set of metric atlases for MWF/FA/uFA/CMD, so here is an example of how to use the atlas to create z-score maps.
#Note: As this subject was part of the atlas, their z-score map is not going to show anything unusual. This step is for MS participants/unusual cases.
bash ${script_folder}/zscore.sh -p ${main_folder} -s ${subject}

done 