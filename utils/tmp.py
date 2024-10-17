import pandas as pd    

subject_label = 'sub-01'
session_label = 'ses-01'
age_in_months = 24
PatientSex = 'M'
cleaned_string = 'T1w'

data = [{'subject': subject_label, 'session': session_label, 'dicom_age_in_months': age_in_months, 'sex': PatientSex, 'acquisition': cleaned_string }]  
# Creates DataFrame.  
demo = pd.DataFrame(data)

test_subject_label = demo['subject'].values[0]
print("test_subject_label: ", test_subject_label)
