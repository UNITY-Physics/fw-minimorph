#!/bin/sh
set -x

```
# Module: Pipeline for segmenting infant brain images on Flywheel
# Author: Chiara Casella, Niall Bourke


# Overview:
# This script is designed to segment neonate brain images on Flywheel. The pipeline consists of the following steps:
# 1. Register the input image to an age-specific template image
# 2. Apply the resulting transformations to predefined segmentation priors and segmentation masks (template space), to bring them into the subject's native space
# 3. Segment the input image in native space using ANTs Atropos, with three priors (tissue, CSF, skull)
# 4. Refine the resulting segmentation posteriors to separate the ventricles from the remaining CSF, and the subcortical grey matter areas from the rest of the tissue
# 5. Extract volume estimates from the segmentations

#The Final_segmentation_atlas.nii.gz includes the following labels: supratentorial tissue, supratentorial csf, ventricles, cerebellum, cerebellum csf, brainstem, brainstem_csf, left_thalamus, 
#left_caudate, left_putamen,	left_globus_pallidus,	right_thalamus,	right_caudate,	right_putamen, right_globus_pallidus


# Usage:
# This script is designed to be run as a Flywheel Gear. The script takes two inputs:
# 1. The input image to segment
# 2. The age of the template to use in months (0 in this case?)

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
age=0M

# Define the paths
FLYWHEEL_BASE=/flywheel/v0
INPUT_DIR=$FLYWHEEL_BASE/input/
WORK_DIR=$FLYWHEEL_BASE/work
OUTPUT_DIR=$FLYWHEEL_BASE/output
TEMPLATE_DIR=$FLYWHEEL_BASE/app/templates/${age}/
CONTAINER='[flywheel/ants-segmentation]'
template=${TEMPLATE_DIR}/template_${age}_0p5mm.nii.gz

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

# ##############################################################################

echo -e "\n --- Step 1: Register image to template --- "

# Define outputs in the following steps
native_bet_image=${WORK_DIR}/native_bet_image.nii.gz
native_brain_mask=${WORK_DIR}/native_brain_mask.nii.gz
input_file_DN=${WORK_DIR}/native_image_DN.nii.gz
input_file_BC=${WORK_DIR}/native_image_BC.nii.gz


#denoise, bias correct and bet image to help with registration to template
ants DenoiseImage -i ${input_file} -o ${input_file_DN}
ants N4BiasFieldCorrection -i ${input_file_DN} -o ${input_file_BC}
mri_synthstrip -i ${input_file_BC} -o ${native_bet_image} -m ${native_brain_mask}
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
    "${TEMPLATE_DIR}/prior1_scale.nii.gz"
    "${TEMPLATE_DIR}/prior2_scale.nii.gz"
    "${TEMPLATE_DIR}/prior3_scale.nii.gz"
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
    "${TEMPLATE_DIR}/ventricles_mask_0p55mm.nii.gz"
    "${TEMPLATE_DIR}/BCP_mask_padded_0p55mm.nii.gz"
    "${TEMPLATE_DIR}/cerebellum_mask_dilate_clean_padded_0p55mm.nii.gz"
    "${TEMPLATE_DIR}/callosum_mask_relabelled_padded_0p55mm.nii.gz"
    "${TEMPLATE_DIR}/brainstem_mask_dilate_clean_padded_0p55mm.nii.gz"
)

for item in "${items[@]}"; do
  item_name=$(basename "$item" .nii.gz)
  output_mask="${item_name}.nii.gz"
  if antsApplyTransforms -d 3 -i "${item}" -r ${native_bet_image} -o ${WORK_DIR}/"${output_mask}" -n NearestNeighbor -t ["$AFFINE_TRANSFORM",1] -t "${INVERSE_WARP}"; then
    echo "*** Transforming ${item} ***"
    echo "*** Output: ${WORK_DIR}/"${output_mask}" ***"
  else
    echo "Error: Failed to transform ${item}"
    exit 1
  fi
  sync
done

# Run Atropos
echo -e "\n --- Step 3: Segmenting images --- "
fslmaths ${native_brain_mask} -dilM ${WORK_DIR}/native_brain_mask_dil.nii.gz
sync
antsAtroposN4.sh -d 3 -a ${input_file_BC} -x ${WORK_DIR}/native_brain_mask_dil.nii.gz -p ${WORK_DIR}/prior%d_scale.nii.gz -c 3 -y 1 -w 0.5 -o ${WORK_DIR}/ants_atropos_
sync
echo -e "\n Past Atropos segmentation step "

sleep 3

# Define posterior images from Atropos segmentation (segmentation in native space with 3 priors)
Posterior1=${WORK_DIR}/ants_atropos_SegmentationPosteriors1.nii.gz
Posterior2=${WORK_DIR}/ants_atropos_SegmentationPosteriors2.nii.gz
Posterior3=${WORK_DIR}/ants_atropos_SegmentationPosteriors3.nii.gz


echo -e "\n --- Step 4: Hello MDR, time to refine segmentations --- "
#Refine segmentations to extract ventricles
fslmaths ${Posterior2} -mul ${WORK_DIR}/ventricles_mask_0p55mm.nii.gz ${WORK_DIR}/ventricles_mask_mul
fslmerge -t ${WORK_DIR}/merged_priors.nii.gz ${Posterior1} ${Posterior2} ${WORK_DIR}/ventricles_mask_mul.nii.gz ${Posterior3}
sync
fslmaths ${WORK_DIR}/merged_priors.nii.gz -Tmean -mul $(fslval ${WORK_DIR}/merged_priors.nii.gz dim4) ${WORK_DIR}/merged_priors_Tsum
fslmaths ${WORK_DIR}/merged_priors_Tsum.nii.gz -thr 1.1 -bin ${WORK_DIR}/subtractmask
fslmaths ${Posterior2} -mul ${WORK_DIR}/subtractmask ${WORK_DIR}/ventricles
fslmaths ${Posterior2} -sub ${WORK_DIR}/ventricles.nii.gz ${WORK_DIR}/csf
fslmaths ${native_brain_mask} -mul 0 ${WORK_DIR}/zero_filled_image.nii.gz
fslmerge -t ${WORK_DIR}/merged_priors.nii.gz ${WORK_DIR}/zero_filled_image.nii.gz ${Posterior1} ${WORK_DIR}/csf.nii.gz ${WORK_DIR}/ventricles.nii.gz ${Posterior3}
sync
fslmaths ${WORK_DIR}/merged_priors.nii.gz -Tmaxn ${WORK_DIR}/temp_atlas.nii.gz #total tissue, csf, ventricles

# Short pause of 3 seconds
sleep 3

echo -e "\n --- Step 5: Build the final segmentation atlas --- "
#Extract subcortical GM
if fslmaths ${WORK_DIR}/temp_atlas.nii.gz -thr 1 -uthr 1 -mul ${WORK_DIR}/BCP_mask_padded_0p55mm.nii.gz ${WORK_DIR}/sub_GM_mask_mul && \
  fslmaths ${WORK_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/sub_GM_mask_mul.nii.gz ${WORK_DIR}/temp_atlas.nii.gz; then #total tissue, csf, ventricles, subcortical GM
  echo "Atlas with subcortical GM created successfully."
else
  echo "Error: Failed to create atlas with subcortical GM."
fi

sync

echo "Adding the cerebellum to the atlas..."
# Extract cerebellum and cerebellum CSF

if fslmaths ${WORK_DIR}/temp_atlas.nii.gz -thr 1 -uthr 2 -mul ${WORK_DIR}/cerebellum_mask_dilate_clean_padded_0p55mm.nii.gz ${WORK_DIR}/cerebellum_mask_mul && \
  fslmaths ${WORK_DIR}/cerebellum_mask_mul -thr 30 -uthr 30 ${WORK_DIR}/cerebellum.nii.gz && \
  fslmaths ${WORK_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/cerebellum ${WORK_DIR}/temp_atlas.nii.gz && \
  fslmaths ${WORK_DIR}/cerebellum_mask_mul -thr 60 -uthr 60 -div 60 -mul 30 ${WORK_DIR}/cerebellum_csf.nii.gz && \
  fslmaths ${WORK_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/cerebellum_csf ${WORK_DIR}/temp_atlas.nii.gz; then
  echo "Atlas with cerebellum created successfully."
else
  echo "Error: Failed to add cerebellum to the atlas."
fi

echo "Adding the brainstem to the atlas..."
#Extract the brainstem and brainstem csf

if fslmaths ${WORK_DIR}/temp_atlas.nii.gz -thr 1 -uthr 2 -mul ${WORK_DIR}/brainstem_mask_dilate_clean_padded_0p55mm.nii.gz ${WORK_DIR}/brainstem_mask_mul && \
  fslmaths ${WORK_DIR}/brainstem_mask_mul -thr 40 -uthr 40 ${WORK_DIR}/brainstem.nii.gz && \
  fslmaths ${WORK_DIR}/temp_atlas -add ${WORK_DIR}/brainstem ${WORK_DIR}/temp_atlas.nii.gz && \
  fslmaths ${WORK_DIR}/brainstem_mask_mul -thr 80 -uthr 80 -div 80 -mul 40 ${WORK_DIR}/brainstem_csf.nii.gz && \
  fslmaths ${WORK_DIR}/temp_atlas.nii.gz -add ${WORK_DIR}/brainstem_csf ${WORK_DIR}/Final_segmentation_atlas.nii.gz; then
  echo "Atlas with brainstem created successfully." 
#Supratentorial tissue, supratentorial csf, ventricles, subcortical GM (left/right caudate, putamen, thalamus, globus pallidus), cerebellum, cerebellum CSF, brainstem, brainstem CSF
else
  echo "Error: Failed to add brainstem to the atlas."
fi


# Short pause of 3 seconds
sleep 3

#Slicer for QC
echo -e "\n --- Step 6: Run slicer and extract volume estimation from segmentations --- "
slicer ${native_bet_image} ${native_bet_image} -a ${WORK_DIR}/slicer_bet.png

slicer ${WORK_DIR}/Final_segmentation_atlas.nii.gz ${WORK_DIR}/Final_segmentation_atlas.nii.gz -a ${WORK_DIR}/slicer_seg1.png
pngappend ${WORK_DIR}/slicer_bet.png - ${WORK_DIR}/slicer_seg1.png ${WORK_DIR}/montage_final_segmentation_atlas.png

# Extract volumes of segmentations
output_csv=${WORK_DIR}/All_volumes.csv
# Initialize the master CSV file with headers
echo "template_age supratentorial_tissue supratentorial_csf ventricles cerebellum cerebellum_csf brainstem brainstem_csf left_thalamus left_caudate left_putamen left_globus_pallidus right_thalamus right_caudate right_putamen right_globus_pallidus icv" > "$output_csv"

atlas=${WORK_DIR}/Final_segmentation_atlas_with_callosum.nii.gz

# Extract volumes for each label
            supratentorial_general=$(fslstats ${atlas} -l 0.5 -u 1.5 -V | awk '{print $2}')
            supratentorial_csf=$(fslstats ${atlas} -l 1.5 -u 2.5 -V | awk '{print $2}')
            ventricles=$(fslstats ${atlas} -l 2.5 -u 3.5 -V | awk '{print $2}')
            cerebellum=$(fslstats ${atlas} -l 30.5 -u 31.5 -V | awk '{print $2}')
            cerebellum_csf=$(fslstats ${atlas} -l 31.5 -u 32.5 -V | awk '{print $2}')
            brainstem=$(fslstats ${atlas} -l 40.5 -u 41.5 -V | awk '{print $2}')
            brainstem_csf=$(fslstats ${atlas} -l 41.5 -u 42.5 -V | awk '{print $2}')
            left_thalamus=$(fslstats ${atlas} -l 16.5 -u 17.5 -V | awk '{print $2}')
            left_caudate=$(fslstats ${atlas} -l 17.5 -u 18.5 -V | awk '{print $2}')
            left_putamen=$(fslstats ${atlas} -l 18.5 -u 19.5 -V | awk '{print $2}')
            left_globus_pallidus=$(fslstats ${atlas} -l 19.5 -u 20.5 -V | awk '{print $2}')
            right_thalamus=$(fslstats ${atlas} -l 26.5 -u 27.5 -V | awk '{print $2}')
            right_caudate=$(fslstats ${atlas} -l 27.5 -u 28.5 -V | awk '{print $2}')
            right_putamen=$(fslstats ${atlas} -l 28.5 -u 29.5 -V | awk '{print $2}')
            right_globus_pallidus=$(fslstats ${atlas} -l 29.5 -u 30.5 -V | awk '{print $2}')

            # Calculate supratentorial tissue volume (include all relevant regions)
            supratentorial_tissue=$(echo "$supratentorial_general + $left_thalamus + $left_caudate + $left_putamen + $left_globus_pallidus + $right_thalamus + $right_caudate + $right_putamen + $right_globus_pallidus" | bc)

            # Calculate ICV
            icv=$(echo "$supratentorial_tissue + $supratentorial_csf + $cerebellum + $cerebellum_csf + $brainstem + $brainstem_csf" | bc)


echo "$age $supratentorial_tissue $supratentorial_csf $ventricles $cerebellum $cerebellum_csf $brainstem $brainstem_csf $left_thalamus $left_caudate $left_putamen $left_globus_pallidus $right_thalamus $right_caudate $right_putamen $right_globus_pallidus $icv" >> "$output_csv"

echo "Volumes extracted and saved to $output_csv"










