
OUTPUT_DIR=/flywheel/v0/output/
WORK_DIR=/flywheel/v0/work/
age=30

# Extract volumes of segmentations
output_csv=${WORK_DIR}/All_volumes.csv

# Initialize the master CSV file with headers
echo "template_age, supratentorial_tissue, supratentorial_csf, ventricles, cerebellum, cerebellum_csf, brainstem, brainstem_csf, left_thalamus, left_caudate, left_putamen, left_globus_pallidus, right_thalamus, right_caudate, right_putamen, right_globus_pallidus, posterior_callosum, mid_posterior_callosum, central_callosum, mid_anterior_callosum, anterior_callosum, icv" > "$output_csv"

atlas=`ls ${OUTPUT_DIR}/*segmentation.nii.gz`

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
            posterior_callosum=$(fslstats ${atlas} -l 7.5 -u 8.5 -V | awk '{print $2}')
            mid_posterior_callosum=$(fslstats ${atlas} -l 8.5 -u 9.5 -V | awk '{print $2}')
            central_callosum=$(fslstats ${atlas} -l 9.5 -u 10.5 -V | awk '{print $2}')
            mid_anterior_callosum=$(fslstats ${atlas} -l 10.5 -u 11.5 -V | awk '{print $2}')
            anterior_callosum=$(fslstats ${atlas} -l 11.5 -u 12.5 -V | awk '{print $2}')

            # Calculate supratentorial tissue volume (include all relevant regions)
            supratentorial_tissue=$(echo "$supratentorial_general + $left_thalamus + $left_caudate + $left_putamen + $left_globus_pallidus + $right_thalamus + $right_caudate + $right_putamen + $right_globus_pallidus + $posterior_callosum + $mid_posterior_callosum + $central_callosum + $mid_anterior_callosum + $anterior_callosum" | bc)

            # Calculate ICV
            icv=$(echo "$supratentorial_tissue + $supratentorial_csf + $cerebellum + $cerebellum_csf + $brainstem + $brainstem_csf" | bc)


echo "$age, $supratentorial_tissue, $supratentorial_csf, $ventricles, $cerebellum, $cerebellum_csf, $brainstem, $brainstem_csf, $left_thalamus, $left_caudate, $left_putamen, $left_globus_pallidus, $right_thalamus, $right_caudate, $right_putamen, $right_globus_pallidus, $posterior_callosum, $mid_posterior_callosum, $central_callosum, $mid_anterior_callosum, $anterior_callosum, $icv" >> "$output_csv"

echo "Volumes extracted and saved to $output_csv"