#MRtrix preprocessing

# data needs to be in bids format. DTI images need both forward and reverse encoded images
#generally AP and PA
#each participant needs 8 files - dwi.nii.gz, dwi.bval, dwi.bvec and dwi.json in both 
# AP and PA

#step one - make .mif files (that stitches together bval, bvec files to the .nii)

mrconvert sub-048_ses-02_acq-b25001000d060306orig_dir-AP_dwi.nii.gz -fslgrad sub-048_ses-02_acq-b25001000d060306orig_dir-AP_dwi.bvec sub-048_ses-02_acq-b25001000d060306orig_dir-AP_dwi.bval sub-048_dwi.mif 

#do this for each participant and run

#relabel bval, bvec files so easy to read

mv sub-048_ses-02_acq-b25001000d060306orig_dir-AP_dwi.bvec sub-048_AP.bvec
mv sub-048_ses-02_acq-b25001000d060306orig_dir-AP_dwi.bval sub-048_AP.bval
mv sub-048_ses-02_acq-b0orig_dir-PA_dwi.bvec sub-048_PA.bvec
mv sub-048_ses-02_acq-b0orig_dir-PA_dwi.bval sub-048_PA.bval

#check the scan information using

mrinfo sub-048_dwi.mif 

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

mrinfo -size sub-048_dwi.mif | awk '{print $4}'
awk '{print NF; exit}' sub-048_AP.bvec
awk '{print NF; exit}' sub-048_AP.bval

#time to start preprocessing. the first step is to denoise the data

dwidenoise sub-048_dwi.mif sub-048_den.mif -noise noise.mif  #~3-4mins

#only takes a few minutes
#now check if the residuals load onto any part of the anatomy. it may 
#indicate that some part of the anatomy was disproportionaly affected by an artifact or distortion
# using mrcalc calculate the residuals - you use the dwi image, and subract the denoised image
#then view the image using mrview. It should be a homogenous grey with no distinct image of the brain.


mrcalc sub-048_dwi.mif sub-048_den.mif -subtract residual.mif

#view distortions
mrview residual.mif

#Converting the PA Images:
#your imaging data should have two sets of files AP (primary phase encoding direction) and PA (reverse phase encoding direction)
#the reverse PA scan is used to unwarp the AP scans. we use both to create and average 
#and cancel out the effects of warping

#first convert PA to .mif format and add bvals, bvecs into the header images.
  
mrconvert sub-048_ses-02_acq-b0orig_dir-PA_dwi.nii.gz PA.mif

#takes the two b0 images and take the mrmath command takes the mean of the two images
#and creates a mean b0.mif file
#dont need to do this for PA - because there is only one.
#mrconvert PA.mif -fslgrad sub-048_PA.bvec sub-048_PA.bval - | mrmath - mean mean_b0_PA.mif -axis 3

#next we extract the bvalues from the primany pahse encoded image and the combine the two 
#using the command mrcat

#Extracting b0 images from the AP dataset, and concatenating the b0 images across both AP and PA images:
  
dwiextract sub-048_den.mif - -bzero | mrmath - mean mean_b0_AP.mif -axis 3

#concatenates the mean b0 images from both phase encoding positions AP & PA 
mrcat mean_b0_AP.mif PA.mif -axis 3 b0_pair.mif

mrcat PA.mif sub-048_den.mif sub-048_concat.mif 
#now the data is ready for the main preprocessing step which uses different commannds 
#to unwarp the data and remove eddy currents

#Preprocessing with dwifslpreproc:
# -pe_dir AP says the primany phase encoding direction is AP -rpe_pair and -se_epi say that the next file is a spin echo 
#image acquired with reverse phase encoded directions. -eddy_options allows selection of many options --slm-linear (better for less than 60 directions)
# and --data_is_shelled is for images collected with more than one b value
# this step can take several hours depending on your computer 

dwifslpreproc sub-048_den.mif sub-048_den_preproc.mif -nocleanup -pe_dir AP -rpe_pair -se_epi b0_pair.mif -eddy_options " --slm=linear --data_is_shelled"



