#!/bin/bash

#MRtrix preprocessing

#setup on CVL

cd /scratch/${USER}/DWI_prep

output_dir=/scratch/${USER}/DWI_prep_output

subjnames=~/STIMdMRI/tom/subjnames.txt
for subjName in `cat ${subjnames}` ; do 
for ses in 02 03 ; do 
    ml mrtrix3
    bids_dir=/RDS/Q1876/data/bids/${subjName}/ses-${ses}/

# data needs to be in bids format. DTI images need both forward and reverse encoded images
#generally AP and PA
#each participant needs 8 files - dwi.nii.gz, dwi.bval, dwi.bvec and dwi.json in both 
# AP and PA

#step one - make .mif files (that stitches together bval, bvec files to the .nii)

mrconvert ${bids_dir}/${subjName}_ses-${ses}_acq-*orig*AP_dwi.nii.gz \
-fslgrad ${bids_dir}/${subjName}_ses-${ses}_acq-*AP_dwi.bvec \
${bids_dir}/${subjName}_ses-${ses}_acq-*AP_dwi.bval \
${bids_dir}/${subjName}_ses-${ses}_dwi.mif 


#check the scan information using

mrinfo ${bids_dir}/${subjName}_ses-${ses}_dwi.mif  

#it will look something like this. check the dimenstions, the first 3 are voxels the 
#fourth is time, or the number of volumes. Each file, the mifs, .nii, .bval, bvec, need to have specific values that match the 
#number of volumes

#mrinfo sub-02_dwi.mif 
# ************************************************
#   Image name:          "sub-02_dwi.mif"
# ************************************************
#   Dimensions:        96 x 96 x 60 x 102
# Voxel size:        2.5 x 2.5 x 2.5 x 8.7
# Data strides:      [ -1 2 3 4 ]
# Format:            MRtrix
# Data type:         signed 16 bit integer (little endian)
# Intensity scaling: offset = 0, multiplier = 1
# Transform:               0.9988    -0.01395     0.04747        -111
# 0.02082      0.9888     -0.1476      -85.88
# -0.04488      0.1484      0.9879      -56.76
# command_history:   mrconvert sub-CON02_ses-preop_acq-AP_dwi.nii.gz sub-02_dwi.mif -fslgrad sub-CON02_ses-preop_acq-AP_dwi.bvec sub-CON02_ses-preop_acq-AP_dwi.bval  (version=3.0.2)
# comments:          TE=1.1e+02;Time=125448.950;phase=1;dwell=0.380
# dw_scheme:         0,0,0,0
# [102 entries]      0,0,0,0
# ...
# 0.9082055818,0.3669468842,-0.201277434,2800
# 0,0,0,0
# mrtrix_version:    3.0.2

#checking file sizes 
#mrinfo -size sub-02_dwi.mif | awk '{print $4}'
#awk '{print NF; exit}' sub-02_AP.bvec
#awk '{print NF; exit}' sub-02_AP.bval
#time to start preprocessing. the first step is to denoise the data
dwidenoise ${bids_dir}/${subjName}_ses-${ses}_dwi.mif \
${bids_dir}/${subjName}_ses-${ses}_dwi_den.mif \
-noise noise.mif  #~3-4mins

#only takes a few minutes
#now check if the residuals load onto any part of the anatomy. it may 
#indicate that some part of the anatomy was disproportionaly affected by an artifact or distortion
# using mrcalc calculate the residuals - you use the dwi image, and subract the denoised image
#then view the image using mrview. It should be a homogenous grey with no distinct image of the brain.
mrcalc ${bids_dir}/${subjName}_ses-${ses}_dwi.mif \
${bids_dir}/${subjName}_ses-${ses}_dwi_den.mif \
-subtract ${bids_dir}/${subjName}_ses-${ses}_residual.mif 
#view distortions (need to do this in command line)
#mrview ${bids_dir}/${subjName}_ses-${ses}_residual.mif
#Converting the PA Images:
#your imaging data should have two sets of files AP (primary phase encoding direction) and PA (reverse phase encoding direction)
#the reverse PA scan is used to unwarp the AP scans. we use both to create and average 
#and cancel out the effects of warping
#first convert PA to .mif format and add bvals, bvecs into the header images.
mrconvert ${bids_dir}/${subjName}_ses-${ses}_acq-*PA_dwi.nii.gz \
${bids_dir}/${subjName}_ses-${ses}_PA.mif
#next we extract the bvalues from the primany pahse encoded image and the combine the two 
#using the command mrcat
#Extracting b0 images from the AP dataset, and concatenating the b0 images across both AP and PA images:
dwiextract ${bids_dir}/${subjName}_ses-${ses}_dwi_den.mif \
-bzero | mrmath - mean ${bids_dir}/${subjName}_ses-${ses}_mean_b0_AP.mif \
-axis 3
#concatenates the mean b0 images from both phase encoding positions AP & PA 
mrcat ${bids_dir}/${subjName}_ses-${ses}_mean_b0_AP.mif \
${bids_dir}/${subjName}_ses-${ses}_PA.mif \
-axis 3 \
${bids_dir}/${subjName}_ses-${ses}_B0_pair.mif
mrcat ${bids_dir}/${subjName}_ses-${ses}_PA.mif \
${bids_dir}/${subjName}_ses-${ses}_dwi_den.mif \
${bids_dir}/${subjName}_ses-${ses}_concat.mif 

#now the data is ready for the main preprocessing step which uses different commannds 
#to unwarp the data and remove eddy currents
#Preprocessing with dwifslpreproc:
# -pe_dir AP says the primany phase encoding direction is AP -rpe_pair and -se_epi say that the next file is a spin echo 
#image acquired with reverse phase encoded directions. -eddy_options allows selection of many options --slm-linear (better for less than 60 directions)
# and --data_is_shelled is for images collected with more than one b value
# this step can take several hours depending on your computer 
dwifslpreproc ${bids_dir}/${subjName}_ses-${ses}_dwi_den.mif \
${bids_dir}/${subjName}_ses-${ses}_den_preproc.mif \
-nocleanup \
-pe_dir AP \
-rpe_pair \
-se_epi ${bids_dir}/${subjName}_ses-${ses}_B0_pair.mif \
-eddy_options " --slm=linear --data_is_shelled"

#Checking the preprocessing output:

#mrview sub-048_den_preproc.mif -overlay.load sub-048_dwi.mif

#Bias-correcting the data and creating a mask:

dwibiascorrect ants ${bids_dir}/${subjName}_ses-${ses}_den_preproc.mif \
${bids_dir}/${subjName}_ses-${ses}_den_preproc_unbiased.mif \
-bias ${bids_dir}/${subjName}_ses-${ses}_bias.mif \
dwi2mask ${bids_dir}/${subjName}_ses-${ses}_den_preproc_unbiased.mif \
${bids_dir}/${subjName}_ses-${ses}_mask.mif 

#mrview mask.mif

#Estimating the Basis Functions:
dwi2response dhollander ${bids_dir}/${subjName}_ses-${ses}_den_preproc_unbiased.mif \
${bids_dir}/${subjName}_ses-${ses}_wm.txt \
${bids_dir}/${subjName}_ses-${ses}_gm.txt \
${bids_dir}/${subjName}_ses-${ses}_csf.txt \
-voxels ${bids_dir}/${subjName}_ses-${ses}_voxels.mif

#Viewing the Basis Functions:

#mrview sub-048_den_preproc_unbiased.mif -overlay.load voxels.mif
#shview wm.txt
#shview gm.txt
#shview csf.txt
#Applying the basis functions to the diffusion data:

dwi2fod msmt_csd \
${bids_dir}/${subjName}_ses-${ses}_den_preproc_unbiased.mif \
-mask ${bids_dir}/${subjName}_ses-${ses}_mask.mif \
${bids_dir}/${subjName}_ses-${ses}_wm.txt \
${bids_dir}/${subjName}_ses-${ses}_wmfod.mif \
${bids_dir}/${subjName}_ses-${ses}_gm.txt \
${bids_dir}/${subjName}_ses-${ses}_gmfod.mif \
${bids_dir}/${subjName}_ses-${ses}_csf.txt \
${bids_dir}/${subjName}_ses-${ses}_csffod.mif


#Concatenating the FODs:

mrconvert -coord 3 0 ${bids_dir}/${subjName}_ses-${ses}_wmfod.mif - | mrcat ${bids_dir}/${subjName}_ses-${ses}_csffod.mif \
${bids_dir}/${subjName}_ses-${ses}_gmfod.mif - ${bids_dir}/${subjName}_ses-${ses}_vf.mif

#Viewing the FODs:

#mrview vf.mif -odf.load_sh wmfod.mif


#Normalizing the FODs:

mtnormalise ${bids_dir}/${subjName}_ses-${ses}_wmfod.mif \
${bids_dir}/${subjName}_ses-${ses}_wmfod_norm.mif \
${bids_dir}/${subjName}_ses-${ses}_gmfod.mif \
${bids_dir}/${subjName}_ses-${ses}_gmfod_norm.mif \
${bids_dir}/${subjName}_ses-${ses}_csffod.mif \
${bids_dir}/${subjName}_ses-${ses}_csffod_norm.mif \
-mask ${bids_dir}/${subjName}_ses-${ses}_mask.mif
done 
done 