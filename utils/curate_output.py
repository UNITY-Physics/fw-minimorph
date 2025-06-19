import flywheel
import json
import pandas as pd
from datetime import datetime
import re
import os
import shutil

import logging


log = logging.getLogger(__name__)


#  Module to identify the correct template use for the subject VBM analysis based on age at scan
#  Need to get subject identifiers from inside running container in order to find the correct template from the SDK
def find_gear_version(analyses, filename):
    for asys in analyses:
        for file in asys.files:
            if file.name == filename:
                if 'gambas' in asys.label:
                    return asys.label.split(' ')[0]
                elif 'mrr' in asys.label:
                    return f"{file.gear_info.name}/{file.gear_info.version}"
    return None
def get_age(session, dicom_header):
    
    # -------------------  Get the subject age & matching template  -------------------  #
    # uploaded demographics the most reliable, after that try to get from dicom header
    # get the T2w axi dicom acquisition from the session
    # Should contain the DOB in the dicom header
    # Some projects may have DOB removed, but may have age at scan in the subject container

    age_source = None
    age = None

    # Check if age is in custom session info
    if session.info.get('age_at_scan_months', None) != None:
        age_source = 'custom_info'
        print(age, age_source)

    else:
        age = re.sub('\D', '', dicom_header.info.get('PatientAge', None))
        # Check for PatientAge in the DICOM header
        if 'PatientAge' != None :
            print("No custom demographic age uploaded in session info! Trying PatientAge from dicom...")
            age_raw = dicom_header.info['PatientAge']

            # Parse age and convert to months
            unit = age_raw[-1].upper()  # Extract the unit (D = Days, W = Weeks, M = Months, Y = Years)
            numeric_age = int(re.sub('\D', '', age_raw))  # Remove non-numeric characters

            if unit == 'D':  # Days to months
                age = numeric_age // 30
            elif unit == 'W':  # Weeks to months
                age = numeric_age // 4
            elif unit == 'M':  # Already in months
                age = numeric_age
            elif unit == 'Y':  # Years to months
                age = numeric_age * 12
            else:
                print("Unknown unit for PatientAge. Setting age to NA.")
                age = 'NA'

            age_source = 'dicom_age'

        # If PatientAge is unavailable or invalid, fallback to PatientBirthDate and SeriesDate
        dob = dicom_header.info.get('PatientBirthDate', None)
        series_date = dicom_header.get('SeriesDate', None)
        
        if age is None or age == 0:
            if dob != None and series_date != None:
                print("Trying DOB from dicom...")
                print("WARNING: This may be inaccurate if false DOB was entered at time of scanning!")
                # Calculate age at scan
                # Calculate the difference in months
                try:
                    series_dt = datetime.strptime(series_date, '%Y%m%d')
                    dob_dt = datetime.strptime(dob, '%Y%m%d')

                    dob_dt = datetime.strptime(dob, '%Y%m%d')
                    series_date_dt = datetime.strptime(series_date, '%Y%m%d')
                    age_days = (series_date_dt - dob_dt).days

                    # Convert days to months
                    age = age_days // 30
                    age_source = 'dicom_DOB'

                except Exception as e:
                    print(f"Error parsing dates from dicom: {e}")
                    age = 'NA'
                    age_source = 'NA'

                # Adjust if the day in series_dt is earlier than the day in dob_dt
                if series_dt.day < dob_dt.day:
                    age = 'NA'
                    age_source = 'NA'

            else:
                print("No valid birthdate or series date found in dicom header. Setting age to NA.")
                age = 'NA'
                age_source = 'NA'


    print(age, age_source)
    return age, age_source

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
    log.info(f"subject label: {subject.label}")
    subject_label = subject.label

    # Get the session id from the input file id
    # & extract the session container
    session_id = input_container.parents['session']
    session_container = context.client.get(session_id)
    session = session_container.reload()
    session_info = session.info
    session_label = session.label
    log.info(f"session label: {session.label}")
    
    # -------------------  Get Acquisition label -------------------  #

    # Specify the directory you want to list files from
    directory_path = '/flywheel/v0/input/input'
    gear_v = 'NA'
    # List all files in the specified directory
    for filename in os.listdir(directory_path):
        if os.path.isfile(os.path.join(directory_path, filename)):
            filename_without_extension = filename.split('.')[0]
            no_white_spaces = filename_without_extension.replace(" ", "")
            # no_white_spaces = filename.replace(" ", "")
            acquisition_cleaned = re.sub(r'[^a-zA-Z0-9]', '_', no_white_spaces)
            acquisition_cleaned = acquisition_cleaned.rstrip('_') # remove trailing underscore
             # default value for gear version
            #look for the file and the mrr/gambas version associated with it

            gear_v = find_gear_version(session.analyses, filename)

            if not gear_v:
                for acq in session.acquisitions():
                    acq = acq.reload()
                    gear_v = find_gear_version(acq.analyses, filename)
                    if gear_v:
                        break
                    
    # -------------------  Get the subject age & matching template  -------------------  #

    # get the T2w axi dicom acquisition from the session
    # Should contain the DOB in the dicom header
    # Some projects may have DOB removed, but may have age at scan in the subject container

    sex,age,age_source = None,None,None
    for acq in session_container.acquisitions.iter():
        # print(acq.label)
        acq = acq.reload()
        if 'T2' in acq.label and 'AXI' in acq.label and 'Segmentation' not in acq.label and 'Align' not in acq.label: 
            for file_obj in acq.files: # get the files in the acquisition
                # Screen file object information & download the desired file
                if file_obj['type'] == 'dicom':
                    
                    dicom_header = fw._fw.get_acquisition_file_info(acq.id, file_obj.name)
                    age, age_source = get_age(session, dicom_header)
                    scannerSoftwareVersion = dicom_header.info.get('SoftwareVersions', None)

                    try:
                        sex = session_info.get("sex_at_birth", dicom_header.info.get("PatientSex","NA"))
                    except:
                        continue
                    

    
    # assign values to lists. 
    data = [{'subject': subject_label, 'session': session_label, 'age': age, 'age_source': age_source, 'sex': sex, 'acquisition': acquisition_cleaned, "input_gear_v": gear_v, "scanner_software_v": scannerSoftwareVersion }]  
    # Creates DataFrame.  
    demo = pd.DataFrame(data)

    log.info(f"Demographics:  {subject_label} {session_label} {str(age_in_months)} {sex}")

    return demo

    # -------------------  Concatenate the data  -------------------  #

def housekeeping(demographics):

    acq = demographics['acquisition'].values[0]
    sub = demographics['subject'].values[0]

    filePath = '/flywheel/v0/work/All_volumes.csv'
    volumes = pd.read_csv(filePath, sep='\s+', engine='python') #index_col=False,
    df = pd.concat([demographics.reset_index(drop=True), volumes.reset_index(drop=True)], axis=1)
    out_name = f"{acq}_volumes.csv"
    outdir = ('/flywheel/v0/output/' + out_name)
    df.to_csv(outdir, index=False)

    seg_file = '/flywheel/v0/work/Final_segmentation_atlas_with_callosum.nii.gz'
    new_seg_file = '/flywheel/v0/output/' + acq + '_segmentation.nii.gz'
    shutil.copy(seg_file, new_seg_file)

    QC_montage = '/flywheel/v0/work/montage_final_segmentation_atlas_with_callosum.png'
    new_QC_montage = '/flywheel/v0/output/' + acq + '_QC-montage.png'
    shutil.copy(QC_montage, new_QC_montage)