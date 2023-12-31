# Example usage

Requires: 
- dcm2niix: https://github.com/rordenlab/dcm2niix 
- FSL: https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation 
- ANTs: https://stnava.github.io/ANTs/
- MRTrix3: https://www.mrtrix.org/download/ 
- MD-dMRI: https://github.com/markus-nilsson/md-dmri/ 
- QTI+: https://github.com/ElsevierSoftwareX/SOFTX-D-21-00175 
- Elastix: https://elastix.lumc.nl/ 

The main files here are for processing MWI and TVDE data as in the paper.
This relies on the following file structure to already exist: \
***main folder***\
-- **example_usage.sh script**\
-- **Metric atlases folder, named "atlas"**\
-- **Study-specific tract folder, named "group_tractography"**\
-- **sample subject folder**\
---- PARREC\
------ *At least PARRECs of LTE, STE, PTE, Rev b0, 3DT1*\
---- CALIPR\
------ *CALIPR 56 echoes, MWF map*\
-- **subject 2 folder** \
-- **subject 3 folder** \
etc.

The example_usage.sh file shows how the scripts can be run on sample data. \
Sample data lives at DOI: 10.5281/zenodo.8339144. There are 3 zip files: SAMPLE.zip contains a healthy
particpant's data (fully processed), atlas.zip contains metric atlases and group_tractography.zip
contains components related to the study-specific tract atlas. \
Please download, unzip and put into the file structure above to be able to run this script on the sample data.
In the scripts, you will need to modify some file paths to match your system. Specifically,
- In example_usage.sh, modify paths at the top of the file showing data storage location
- In processing/MDD_setup.m, modify the path to the MD-DMRI library
- In processing/QTIPlus.m, modify the path to the QTI+ library

NIFTITOOLS (https://www.mathworks.com/matlabcentral/fileexchange/8797-tools-for-nifti-and-analyze-image), 
the NKI template for brain extraction (https://figshare.com/articles/dataset/ANTs_ANTsR_Brain_Templates/915436), 
ROIs from the JHU-ICBM template, and the MNI152 1mm T1 template (https://web.mit.edu/fsl_v5.0.10/fsl/doc/wiki/Atlases.html)
are already included here for convenience.