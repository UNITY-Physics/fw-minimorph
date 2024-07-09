#!/bin/sh

```
# Module: For running the ANTs pipeline for segmenting infant brain images on Flywheel
# Author: Chiara Casella, Niall Bourke


# Overview:
# This script is designed to run the ANTs pipeline for segmenting infant brain images on Flywheel. The pipeline consists of the following steps:
# 1. Register the input image to a template image
# 2. Apply the registration to the input image
# 3. Segment the input image in template space using ANTs Atropos
# 4. Move the segmentations back to native space
# 5. Extract volume estimates from the segmentations


# Usage:
# This script is designed to be run as a Flywheel Gear. The script takes two inputs:
# 1. The input image to segment
# 2. The age of the template to use in months (e.g. 3, 6, 12, 24, 48, 72)

# The script assumes that the input image is in NIfTI format. The script outputs the segmentations in native space.


# NOTE:
# Need txt output of volumes
# clean up intermediate files
# slicer bet & segmentations in native space (-A)

```

# Initialise the FSL environment
. ${FSLDIR}/etc/fslconf/fsl.sh

# Add c3d to the path
export PATH=$PATH:/flywheel/v0/utils/c3d-1.1.0/bin/c3d_affine_tool

#Define inputs
input_file=$1
age=$2

# Define the paths
FLYWHEEL_BASE=/flywheel/v0
INPUT_DIR=$FLYWHEEL_BASE/input/
WORK_DIR=$FLYWHEEL_BASE/work
OUTPUT_DIR=$FLYWHEEL_BASE/output
TEMPLATE_DIR=$FLYWHEEL_BASE/app/templates/${age}/
CONTAINER='[flywheel/ants-segmentation]'
template=${TEMPLATE_DIR}/template_${age}_degibbs.nii.gz

echo "permissions"
ls -ltra /flywheel/v0/

##############################################################################
# Handle INPUT file
# Check that input file exists

if [[ -e $input_file ]]; then
  echo "${CONTAINER}  Input file found: ${input_file}"

    # Determine the type of the input file
  if [[ "$input_file" == *.nii ]]; then
    type=".nii"
  elif [[ "$input_file" == *.nii.gz ]]; then
    type=".nii.gz"
  fi
  # Get the base filename
  # base_filename=`basename "$input_file" $type`
  native_img=`basename $input_file`
  native_img="${native_img%.nii.gz}"

else
  echo "${CONTAINER} no inputs were found within input directory $INPUT_DIR"
  exit 1
fi

##############################################################################

echo -e "\n --- Step 1: Register image to template --- "

# Define outputs in the following steps
native_bet_image=${OUTPUT_DIR}/native_bet_image.nii.gz
native_brain_mask=${OUTPUT_DIR}/native_brain_mask.nii.gz
template_brain_mask=${OUTPUT_DIR}/brainMask_dil.nii.gz

#bet image to help with registration to template
# mri_synthstrip -i ${input_file} -o ${OUTPUT_DIR}/native_bet_image.nii.gz -m ${OUTPUT_DIR}/native_brain_mask.nii.gz
bet ${input_file} ${native_bet_image}
fslmaths ${native_bet_image} -bin ${native_brain_mask}
echo "BET image and mask created"
ls ${native_bet_image} ${native_brain_mask}
echo "***"  
# Dilate template brain mask
echo "Dilating template brain mask"
fslmaths ${TEMPLATE_DIR}/brainMask.nii.gz -dilM ${OUTPUT_DIR}/brainMask_dil.nii.gz

# Register native BET image to template brain
echo "Registering native BET image to template brain"
flirt -in ${native_bet_image} -ref ${template} -refweight ${template_brain_mask} -inweight ${native_brain_mask} -dof 12 -interp spline -omat ${WORK_DIR}/flirt.mat -out ${WORK_DIR}/flirt.nii
echo "flirt done"
ls ${WORK_DIR}/flirt.mat
echo "***"
/flywheel/v0/utils/c3d-1.1.0/bin/c3d_affine_tool -ref ${template} -src ${native_bet_image} ${WORK_DIR}/flirt.mat -fsl2ras -oitk ${WORK_DIR}/itk.txt
echo "c3d_affine_tool done"
ls ${WORK_DIR}/itk.txt
echo "***"
# Run SyN registration
antsRegistrationSyN.sh -d 3 -i ${WORK_DIR}/itk.txt -t 'so' -f ${template} -m ${native_bet_image} -j 1 -o ${OUTPUT_DIR}/bet_ -n 4

# --- Step 2: Apply registration to non-betted image --- #

# Get the affine and warp files from the registration
AFFINE_TRANSFORM=$(ls ${WORK_DIR}/*0GenericAffine.mat)
WARP=$(ls ${WORK_DIR}/*1Warp.nii.gz)
INVERSE_WARP=$(ls ${WORK_DIR}/*1InverseWarp.nii.gz)

# Transform raw input image to template space using the affine warp
echo "Transforming raw input image to template space"
antsApplyTransforms -d 3 -i ${input_file} -r ${template} -o ${WORK_DIR}/warped_to_template.nii.gz -t "$WARP" -t "$AFFINE_TRANSFORM"

# Short pause of 3 seconds
sleep 3

#Multiply by template mask
fslmaths ${WORK_DIR}/warped_to_template.nii.gz -mul ${template_brain_mask} ${WORK_DIR}/img_for_segmentation

echo -e "\n--- Step 3: Segment image in template space with antsAtropos (3 priors) ---" 
# Select the image to segment
img=${WORK_DIR}/img_for_segmentation

# Run Atropos
antsAtroposN4.sh -d 3 -a ${img}.nii.gz -x ${TEMPLATE_DIR}/brainMask.nii.gz -p ${TEMPLATE_DIR}/prior%d.nii.gz -c 3 -y 1 -y 2 -y 3 -w 0.6 -o ants_atropos_

# 4 tissue prior Chiara wants to use
# antsAtroposN4.sh -d 3 -a ${img}.nii.gz -x ${TEMPLATE_DIR}/brainMask.nii.gz -p ${TEMPLATE_DIR}/prior%d.nii.gz -c 4 -y 1 -y 2 -y 3 -y 4 -w 0.6 -o ${OUTPUT_DIR}/${img}_ants_atropos_

echo -e "\n --- Step 4: Move segmentations to native space --- "
# For each posterior, move the segmentation to native space using the inverse warp and affine transform
echo "Moving segmentations to native space"

for posterior in 1 2 3; do
    for FILE in $(ls ants_atropos_SegmentationPosteriors${posterior}.nii.gz); do
        echo "${FILE}"
        # Apply the warp and affine transform to the segmentations 
        echo -e "\n native_img: ${native_img}"
        echo -e "\n AFFINE_TRANSFORM: ${AFFINE_TRANSFORM}"
        echo -e "\n INVERSE_WARP: ${INVERSE_WARP}"
        antsApplyTransforms -d 3 -i $FILE -r $input_file -o ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors${posterior}.nii.gz -t ["$AFFINE_TRANSFORM",1] -t $INVERSE_WARP
    done      
done

# Short pause of 3 seconds
sleep 3

echo -e "\n --- Step 5: Run slicer and extract volume estimation from segmentations --- "
slicer ${native_bet_image} ${native_bet_image} -a ${WORK_DIR}/slicer_bet.png
slicer ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors1.nii.gz ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors1.nii.gz -a ${WORK_DIR}/slicer_seg1.png
slicer ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors2.nii.gz ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors2.nii.gz -a ${WORK_DIR}/slicer_seg2.png
slicer ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors3.nii.gz ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors3.nii.gz -a ${WORK_DIR}/slicer_seg3.png
pngappend ${WORK_DIR}/slicer_bet.png - ${WORK_DIR}/slicer_seg1.png - ${WORK_DIR}/slicer_seg2.png - ${WORK_DIR}/slicer_seg3.png ${OUTPUT_DIR}/montage.png

# Extract volumes of segmentations
fslstats ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors2.nii.gz -k ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors1.nii.gz -V > ${WORK_DIR}/volume_seg1.csv
fslstats ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors2.nii.gz -k ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors2.nii.gz -V > ${WORK_DIR}/volume_seg2.csv
fslstats ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors3.nii.gz -k ${OUTPUT_DIR}/${native_img}_ants_atropos_SegmentationPosteriors3.nii.gz -V > ${WORK_DIR}/volume_seg3.csv 

# --- Handle exit status --- #
# Check if the output directory is empty
if [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "Error: Output directory is empty"
    exit 1
fi







