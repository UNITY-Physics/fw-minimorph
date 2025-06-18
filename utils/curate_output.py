import flywheel
import json
import pandas as pd
from datetime import datetime
import re
import os
import shutil

#  Module to identify the correct template use for the subject VBM analysis based on age at scan
#  Need to get subject identifiers from inside running container in order to find the correct template from the SDK

def demo(context):

    # Initialize variables
    data = []
    age_in_months = 'NA'
    sex = 'NA'
    
    # Read config.json file
    p = open('/flywheel/v0/config.json')
    config = json.loads(p.read())

    # Read API key in config file
    api_key = (config['inputs']['api-key']['key'])
    fw = flywheel.Client(api_key=api_key)
    
    # Get the input file id
    input_container = context.client.get_analysis(context.destination["id"])

    # Get the subject id from the session id
    # & extract the subject container
    subject_id = input_container.parents['subject']
    subject_container = context.client.get(subject_id)
    subject = subject_container.reload()
    print("subject label: ", subject.label)
    subject_label = subject.label

    # Get the session id from the input file id
    # & extract the session container
    session_id = input_container.parents['session']
    session_container = context.client.get(session_id)
    session = session_container.reload()
    session_label = session.label
    print("session label: ", session.label)
    
    # -------------------  Get Acquisition label -------------------  #

    # Specify the directory you want to list files from
    directory_path = '/flywheel/v0/input/input'
    # List all files in the specified directory
    for filename in os.listdir(directory_path):
        if os.path.isfile(os.path.join(directory_path, filename)):
            filename_without_extension = filename.split('.')[0]
            no_white_spaces = filename_without_extension.replace(" ", "")
            # no_white_spaces = filename.replace(" ", "")
            acquisition_cleaned = re.sub(r'[^a-zA-Z0-9]', '_', no_white_spaces)
            acquisition_cleaned = acquisition_cleaned.rstrip('_') # remove trailing underscore

            #look for the file and the mrr version associated with it
            for asys in session.analyses:
                
                for file in asys.files:
                    if file.name == filename:
                        if 'gambas' in asys.label:
                            gear_v = asys.label.split(' ')[0]
                        else:
                            gear_v = file.gear_info.name + "/" + file.gear_info.version

    # -------------------  Get the subject age & matching template  -------------------  #

    # get the T2w axi dicom acquisition from the session
    # Should contain the DOB in the dicom header
    # Some projects may have DOB removed, but may have age at scan in the subject container

    for acq in session_container.acquisitions.iter():
        # print(acq.label)
        acq = acq.reload()
        if 'T2' in acq.label and 'AXI' in acq.label and 'Segmentation' not in acq.label and 'Align' not in acq.label: 
            for file_obj in acq.files: # get the files in the acquisition
                # Screen file object information & download the desired file
                if file_obj['type'] == 'dicom':
                    
                    dicom_header = fw._fw.get_acquisition_file_info(acq.id, file_obj.name)
                    
                    try:
                        sex = dicom_header.info.get("PatientSex",session.info.get('sex_at_birth', "NA"))
                        dob = dicom_header.info.get('PatientBirthDate', None)
                        series_date = dicom_header.get('SeriesDate', None)

                        if session.info.get('age_at_scan_months', 0) != 0:
                                print("Checking session info for age at scan in months...")
                                age_in_months = float(session.info.get('age_at_scan_months', 0))


                        elif dob != None and series_date != None:
                            # Calculate age at scan
                            # Calculate the difference in months
                            series_dt = datetime.strptime(series_date, '%Y%m%d')
                            dob_dt = datetime.strptime(dob, '%Y%m%d')

                            age_in_months = (series_dt.year - dob_dt.year) * 12 + (series_dt.month - dob_dt.month)

                            # Adjust if the day in series_dt is earlier than the day in dob_dt
                            if series_dt.day < dob_dt.day:
                                age_in_months -= 1
                        
                        else:
                            print("No DOB in dicom header or age in session info! Trying PatientAge from dicom...")
                            # Need to drop the 'D' from the age and convert to int
                            age_in_months = re.sub('\D', '', dicom_header.info.get('PatientAge', "0"))
                        
                        
                        if age_in_months <= 0 or age_in_months > 1200:  # negative, 0 or 100 years
                            age_in_months = 'NA'
                            raise ValueError(f"Invalid age value: {age_in_months} months")
                        
                    except ValueError as e:
                        print(f"Error processing dates: {e}")
                        raise
    
    #age_in_months = str(age_in_months) + "M"
    # assign values to lists. 
    data = [{'subject': subject_label, 'session': session_label, 'age': age_in_months, 'sex': sex, 'acquisition': acquisition_cleaned , "input_gear_v": gear_v }]  
    # Creates DataFrame.  
    demo = pd.DataFrame(data)
    print("Demographics: ", subject_label, session_label, age_in_months, sex)

    return demo

    # -------------------  Concatenate the data  -------------------  #

def housekeeping(demo):

    acq = demo['acquisition'].values[0]
    sub = demo['subject'].values[0]

    filePath = '/flywheel/v0/work/All_volumes.csv'
    volumes = pd.read_csv(filePath, sep='\s+', engine='python') #index_col=False,
    df = pd.concat([demo.reset_index(drop=True), volumes.reset_index(drop=True)], axis=1)
    out_name = f"{acq}_volumes.csv"
    outdir = ('/flywheel/v0/output/' + out_name)
    df.to_csv(outdir, index=False)

    seg_file = '/flywheel/v0/work/Final_segmentation_atlas_with_callosum.nii.gz'
    new_seg_file = '/flywheel/v0/output/' + acq + '_segmentation.nii.gz'
    shutil.copy(seg_file, new_seg_file)

    QC_montage = '/flywheel/v0/work/montage_final_segmentation_atlas_with_callosum.png'
    new_QC_montage = '/flywheel/v0/output/' + acq + '_QC-montage.png'
    shutil.copy(QC_montage, new_QC_montage)