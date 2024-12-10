#!/bin/sh
set -x

```
# Module: Pipeline for segmenting infant brain images on Flywheel
# Author: Chiara Casella, Niall Bourke


# Overview:
# This script is designed to segment infant brain images on Flywheel. The pipeline consists of the following steps:
# 1. Register the input image to an age-specific template image
# 2. Apply the resulting transformations to predefined segmentation priors and segmentation masks (template space), to bring them into the subject's native space
# 3. Segment the input image in native space using ANTs Atropos, with three priors (tissue, CSF, skull)
# 4. Refine the resulting segmentation posteriors to separate the ventricles from the remaining CSF, and the subcortical grey matter areas from the rest of the tissue
# 5. Extract volume estimates from the segmentations

#The Final_segmentation_atlas.nii.gz includes the following labels: supratentorial tissue, supratentorial csf, ventricles, cerebellum, cerebellum csf, brainstem, brainstem_csf, left_thalamus, 
#left_caudate, left_putamen,	left_globus_pallidus,	right_thalamus,	right_caudate,	right_putamen, right_globus_pallidus

#The Final_segmentation_atlas_with_callosum.nii.gz includes all the labels above, as well as the following callosal parcellations: posterior, mid-posterior, central, mid-anterior, anterior


# Usage:
# This script is designed to be run as a Flywheel Gear. The script takes two inputs:
# 1. The input image to segment
# 2. The age of the template to use in months (e.g. 3, 6, 12, 24, 48, 72)

# The script assumes that the input image is in NIfTI format. The script outputs the segmentations in native space.


# NOTES:
# Need txt output of volumes - I have added commands to extract volumes
# clean up intermediate files - I have saved final files to $OUTPUT_DIR, and intermediate files to $WORK_DIR
# slicer bet & segmentations in native space (-A) - added these too

```

# Initialise the FSL environment
. ${FSLDIR}/etc/fslconf/fsl.sh

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
template=${TEMPLATE_DIR}/template_${age}_degibbs_padded.nii.gz

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
native_bet_image=${WORK_DIR}/native_bet_image.nii.gz
native_brain_mask=${WORK_DIR}/native_brain_mask.nii.gz

#bet image to help with registration to template
mri_synthstrip -i ${input_file} -o ${native_bet_image} -m ${native_brain_mask} -b 4
sync
echo "BET image and mask created"
ls ${native_bet_image} ${native_brain_mask}
echo "***"  

sleep 3

# Register native BET image to template brain
echo "Registering native BET image to template brain"
echo -e "\n Run SyN registration"

antsRegistrationSyN.sh -d 3 -t 's' -f ${template} -m ${native_bet_image} -j 1 -p 'f' -o ${WORK_DIR}/bet_ -n 4
sync
sleep 3
echo "antsRegistrationSyN done"
echo "***"

echo -e "\n --- Step 2: Apply registration to segmentation priors --- "
# Get the affine and warp files from the registration
AFFINE_TRANSFORM=$(ls ${WORK_DIR}/bet*GenericAffine.mat)
WARP=$(ls ${WORK_DIR}/bet*Warp.nii.gz)
INVERSE_WARP=$(ls ${WORK_DIR}/bet*InverseWarp.nii.gz)

# Transform priors (template space) to each subject's native space
echo "Transforming priors to native space for segmentation"
items=(
    "${TEMPLATE_DIR}/prior1_scale_padded.nii.gz"
    "${TEMPLATE_DIR}/prior2_scale_padded.nii.gz"
    "${TEMPLATE_DIR}/prior3_scale_padded.nii.gz"
)

for item in "${items[@]}"; do
item_name=$(basename "$item" .nii.gz)
output_prior="${item_name}.nii.gz"
echo "*** Transforming ${item} ***"
echo "*** Output: ${WORK_DIR}/"${output_prior}" ***"
antsApplyTransforms -d 3 -i "${item}" -r ${native_bet_image} -o ${WORK_DIR}/"${output_prior}" -t ["$AFFINE_TRANSFORM",1] -t "${INVERSE_WARP}" 
sync
echo "$item_name transformed and saved to ${output_prior}"
done

# Transform ventricles and subcortical grey matter masks (template space) to each subject's native space
echo "Transforming masks to native space"
items=(
    "${TEMPLATE_DIR}/ventricles_mask_padded.nii.gz"
    "${TEMPLATE_DIR}/BCP_sub_GM_mask_synthmorph_relabelled_padded.nii.gz"
    "${TEMPLATE_DIR}/cerebellum_mask_dilate_clean_padded.nii.gz"
    "${TEMPLATE_DIR}/callosum_mask_relabelled_padded.nii.gz"
    "${TEMPLATE_DIR}/brainstem_mask_dilate_clean_padded.nii.gz"
)

for item in "${items[@]}"; do
item_name=$(basename "$item" .nii.gz)
output_mask="${item_name}.nii.gz"
antsApplyTransforms -d 3 -i "${item}" -r ${native_bet_image} -o ${WORK_DIR}/"${output_mask}" -n NearestNeighbor -t ["$AFFINE_TRANSFORM",1] -t "${INVERSE_WARP}"
sync
echo "$item_name transformed and saved to ${output_mask}"
done

# Run Atropos
echo -e "\n --- Step 3: Segmenting images --- "
fslmaths ${native_brain_mask} -dilM ${WORK_DIR}/native_brain_mask_dil.nii.gz
sync
antsAtroposN4.sh -d 3 -a ${input_file} -x ${WORK_DIR}/native_brain_mask_dil.nii.gz -p ${WORK_DIR}/prior%d_scale_padded.nii.gz -c 3 -y 1 -y 2 -w 0.3 -o ${WORK_DIR}/ants_atropos_
sync
echo -e "\n Past Atropos segmentation step "

sleep 3

# Define posterior images from Atropos segmentation (segmentation in native space with 3 priors)
Posterior1=${WORK_DIR}/ants_atropos_SegmentationPosteriors1.nii.gz
Posterior2=${WORK_DIR}/ants_atropos_SegmentationPosteriors2.nii.gz
Posterior3=${WORK_DIR}/ants_atropos_SegmentationPosteriors3.nii.gz



#Refine segmentations to extract ventricles
fslmaths ${Posterior2} -mul ${WORK_DIR}/ventricles_mask_padded.nii.gz ${WORK_DIR}/ventricles_mask_mul
fslmerge -t ${WORK_DIR}/merged_priors.nii.gz ${Posterior1} ${Posterior2} ${WORK_DIR}/ventricles_mask_mul.nii.gz ${Posterior3}
sync
fslmaths ${WORK_DIR}/merged_priors.nii.gz -Tmean -mul $(fslval ${WORK_DIR}/merged_priors.nii.gz dim4) ${WORK_DIR}/merged_priors_Tsum
fslmaths ${WORK_DIR}/merged_priors_Tsum.nii.gz -thr 1.1 -bin ${WORK_DIR}/subtractmask
fslmaths ${Posterior2} -mul ${WORK_DIR}/subtractmask ${WORK_DIR}/ventricles
fslmaths ${Posterior2} -sub ${WORK_DIR}/ventricles.nii.gz ${WORK_DIR}/csf
fslmaths ${native_brain_mask} -mul 0 ${WORK_DIR}/zero_filled_image.nii.gz
fslmerge -t ${WORK_DIR}/merged_priors.nii.gz ${WORK_DIR}/zero_filled_image.nii.gz ${Posterior1} ${WORK_DIR}/csf.nii.gz ${WORK_DIR}/ventricles.nii.gz ${Posterior3}
sync
fslmaths ${WORK_DIR}/merged_priors.nii.gz -Tmaxn ${OUTPUT_DIR}/temp_atlas.nii.gz #total tissue, csf, ventricles

# Short pause of 3 seconds
sleep 3


#Extract subcortical GM
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -thr 1 -uthr 1 -mul ${WORK_DIR}/BCP_sub_GM_mask_0.5_resampled_relabelled_padded.nii.gz ${WORK_DIR}/sub_GM_mask_mul
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/sub_GM_mask_mul.nii.gz ${OUTPUT_DIR}/temp_atlas.nii.gz #total tissue, csf, ventricles, subcortical GM
sync


# Extract cerebellum and cerebellum CSF
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -thr 1 -uthr 2 -mul ${WORK_DIR}/cerebellum_mask_dilate_clean_padded.nii.gz ${WORK_DIR}/cerebellum_mask_mul
# Extract cerebellum
fslmaths ${WORK_DIR}/cerebellum_mask_mul -thr 30 -uthr 30 ${WORK_DIR}/cerebellum.nii.gz
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/cerebellum ${OUTPUT_DIR}/temp_atlas.nii.gz
# Extract cerebellum CSF
fslmaths ${WORK_DIR}/cerebellum_mask_mul -thr 60 -uthr 60 -div 60 -mul 30 ${WORK_DIR}/cerebellum_csf.nii.gz
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/cerebellum_csf ${OUTPUT_DIR}/temp_atlas.nii.gz #total tissue, csf, ventricles, subcortical GM, cerebellum, cerebellum CSF
echo "Atlas with cerebellum created successfully."



#now extract the brainstem and brainstem csf
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -thr 1 -uthr 2 -mul ${WORK_DIR}/brainstem_mask_dilate_clean_padded.nii.gz ${WORK_DIR}/brainstem_mask_mul
# Extract brainstem
fslmaths ${WORK_DIR}/brainstem_mask_mul -thr 40 -uthr 40 ${WORK_DIR}/brainstem.nii.gz
fslmaths ${OUTPUT_DIR}/temp_atlas -add ${WORK_DIR}/brainstem ${OUTPUT_DIR}/temp_atlas.nii.gz
# Extract brainstem CSF
fslmaths ${WORK_DIR}/brainstem_mask_mul -thr 80 -uthr 80 -div 80 -mul 40 ${WORK_DIR}/brainstem_csf.nii.gz
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/brainstem_csf ${OUTPUT_DIR}/Final_segmentation_atlas.nii.gz
echo "Atlas with cerebellum created successfully." #total tissue, csf, ventricles, subcortical GM, cerebellum, cerebellum CSF, brainstem, brainstem CSF



#now extract the callosum
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -thr 1 -uthr 1 -mul ${WORK_DIR}/callosum_mask_relabelled_padded.nii.gz ${WORK_DIR}/callosum_mask_mul
fslmaths ${OUTPUT_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/callosum_mask_mul ${WORK_DIR}/Final_segmentation_atlas_with_callosum.nii.gz
echo "Atlas with callosum created successfully."



# Short pause of 3 seconds
sleep 3

#Slicer for QC
echo -e "\n --- Step 5: Run slicer and extract volume estimation from segmentations --- "
slicer ${native_bet_image} ${native_bet_image} -a ${WORK_DIR}/slicer_bet.png

slicer ${OUTPUT_DIR}/atlas_4classes.nii.gz ${OUTPUT_DIR}/Segmentation_atlas_all_classes_with_callosum.nii.gz -a ${WORK_DIR}/slicer_seg1.png
pngappend ${WORK_DIR}/slicer_bet.png - ${WORK_DIR}/slicer_seg1.png ${OUTPUT_DIR}/montage_4_classes.png

slicer ${OUTPUT_DIR}/atlas_5classes.nii.gz ${OUTPUT_DIR}/Segmentation_atlas_all_classes_with_callosum.nii.gz -a ${WORK_DIR}/slicer_seg2.png
pngappend ${WORK_DIR}/slicer_bet.png - ${WORK_DIR}/slicer_seg2.png ${OUTPUT_DIR}/montage_5_classes.png

slicer ${OUTPUT_DIR}/Segmentation_atlas_all_classes_with_callosum.nii.gz ${OUTPUT_DIR}/Segmentation_atlas_all_classes_with_callosum.nii.gz -a ${WORK_DIR}/slicer_seg3.png
pngappend ${WORK_DIR}/slicer_bet.png - ${WORK_DIR}/slicer_seg3.png ${OUTPUT_DIR}/montage_all_classes.png

# Extract volumes of segmentations
output_csv=${WORK_DIR}/All_volumes.csv
# Initialize the master CSV file with headers
echo "template_age total_tissue_volume total_csf_volume tissue_non_sub_GM_non_cerebellum csf_non_ventricles ventricles skull cerebellum posterior_callosum mid_posterior_callosum central_callosum mid_anterior_callosum anterior_callosum left_thalamus left_caudate left_putamen left_globus_pallidus right_thalamus right_caudate right_putamen right_globus_pallidus icv" > "$output_csv"

atlas=${OUTPUT_DIR}/Segmentation_atlas_all_classes_with_callosum.nii.gz
# atlas=${OUTPUT_DIR}/Segmentation_atlas_all_classes.nii.gz

# Calculate the volume of voxels that equal 1
volume_equal_1=$(fslstats ${atlas} -l 0.5 -u 1.5 -V | awk '{print $2}')
# Calculate the volume of voxels that are above 5.5
volume_above_5_5=$(fslstats ${atlas} -l 5.5 -V | awk '{print $2}')
# Sum the above volumes to obtain total tissue volume
total_tissue_volume=$(echo "$volume_equal_1 + $volume_above_5_5" | bc)

total_csf_volume=$(fslstats ${atlas} -l 1.5 -u 3.5 -V | awk '{print $2}')

volumes=`fslstats -K ${atlas} ${atlas} -M -V | sed '/missing/d'| awk '{print $3}'`

# Calculate the volume of voxels below 4
volume_below_4=$(fslstats ${atlas} -u 3.5 -V | awk '{print $2}')
# Calculate the volume of voxels above 4
volume_above_4=$(fslstats ${atlas} -l 4.5 -V | awk '{print $2}')
# Sum the above volumes to obtain intracranial volume
icv=$(echo "$volume_below_4 + $volume_above_4" | bc) 

# Assuming these variables are already defined in your script
# echo "$age,$total_tissue_volume,$total_csf_volume,$volumes,$icv" >> "$output_csv"
echo $age $total_tissue_volume $total_csf_volume $volumes $icv >> $output_csv
echo "Volumes extracted and saved to $output_csv"

# --- Handle exit status --- #
# Check if the output directory is empty
if [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "Error: Output directory is empty"
    exit 1
fi









