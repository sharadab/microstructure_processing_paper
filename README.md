# MWI_TVDE_Microstructure
Myelin water imaging and tensor-valued diffusion imaging processing code. 

Processing steps as used in the paper: "Painting a more complete picture of brain microstructure using myelin water fraction and microscopic fractional anisotropy". Supporting data is available at DOI: 10.5281/zenodo.8339144. 

Requires: 
- dcm2niix: https://github.com/rordenlab/dcm2niix 
- FSL: https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation 
- ANTs: https://stnava.github.io/ANTs/
- MRTrix3: https://www.mrtrix.org/download/ 
- MD-dMRI: https://github.com/markus-nilsson/md-dmri/ 
- QTI+: https://github.com/ElsevierSoftwareX/SOFTX-D-21-00175 
- Elastix: https://elastix.lumc.nl/ 

The processing/ folder contains scripts that break down the whole processing pipeline. 

To repeat steps from the paper, first run initial_processing to create metric maps for a given subject:
> ./initial_processing.sh -p /full/path/to/main/folder -s subject_id

To generate ROIs and extract mean and std values for a given subject:
> ./roi_analysis.sh -p /full/path/to/main/folder -s subject_id 

To create the tractography atlas using several subjects' data:
> ./tractography_atlas.sh -p /full/path/to/main/folder -f subject_file.txt

To process subjects who should not be part of the tract atlas (e.g. MS patients, special cases):
> ./tractography_special_subjects.sh -p /full/path/to/main/folder -s subject_id

To warp tract atlas to a subject and generate tract profiles for each metric for a given subject:
> ./tractometry.sh -p /full/path/to/main/folder -s subject_id

To create metric atlases using several subjects' data:
> ./atlas.sh -p /full/path/to/main/folder -f subject_file.txt

To create z-score maps for a subject based on the metric atlases:
> ./zscore.sh -p /full/path/to/main/folder -s subject_id

The example_usage/ folder contains a script that runs most processing steps, and more details on the sample data.