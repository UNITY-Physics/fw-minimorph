import flywheel
import json
import pandas as pd
from datetime import datetime
import re
import os

#  Module to identify the correct template use for the subject VBM analysis based on age at scan
#  Need to get subject identifiers from inside running container in order to find the correct template from the SDK

def demo(context):

    # Initialize variables
    data = []
    age_in_months = 'NA'
    PatientSex = 'NA'
    
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
    
    try:
        age_in_months = session.info['age_months']
        print("Age in months provided in session info")
        print("Age in months: ", age_in_months)
    except:
        print("No age in months in session info")
        pass

    # -------------------  Get Acquisition label -------------------  #

    # Specify the directory you want to list files from
    directory_path = '/flywheel/v0/input/input'
    # List all files in the specified directory
    for filename in os.listdir(directory_path):
        if os.path.isfile(os.path.join(directory_path, filename)):
            filename_without_extension = filename.split('.')[0]
            no_white_spaces = filename_without_extension.replace(" ", "")
            # no_white_spaces = filename.replace(" ", "")
            cleaned_string = re.sub(r'[^a-zA-Z0-9]', '_', no_white_spaces)
            cleaned_string = cleaned_string.rstrip('_') # remove trailing underscore

    print("cleaned_string: ", cleaned_string)

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
                        PatientSex = dicom_header.info["PatientSex"]
                    except:
                        PatientSex = "NA"
                        continue
                    print("Patient Sex: ", PatientSex)

                    if age_in_months == 'NA':
                        print("No age in months in session demographic sync...")
                        if 'PatientBirthDate' in dicom_header.info:
                            print("Checking DOB in dicom header...")
                            try:
                                dob = dicom_header.info['PatientBirthDate']
                                seriesDate = dicom_header.info['SeriesDate']
                                # Validate date format and presence of SeriesDate
                                if not seriesDate:
                                    raise ValueError("SeriesDate is missing")
                                
                                # Calculate age at scan
                                age = (datetime.strptime(seriesDate, '%Y%m%d')) - (datetime.strptime(dob, '%Y%m%d'))
                                age_in_days = age.days
                                age_in_months = int(age_in_days / 30.44)
                                
                                # Sanity check for negative ages or unreasonable values
                                if age_in_days < 0:
                                    raise ValueError(f"Invalid age calculation: {age_in_days} days")
                                    
                            except ValueError as e:
                                print(f"Error processing dates: {e}")
                                raise

                        elif session.age is not None:  # More pythonic than != None
                            print("Checking session information label...")
                            try:
                                # Convert seconds to days more clearly
                                seconds_per_day = 24 * 60 * 60
                                age_in_days = int(session.age / seconds_per_day)
                                age_in_months = int(age_in_days / 30.44)
                                
                                # Sanity check
                                if age_in_days < 0 or age_in_days > 36500:  # 100 years
                                    raise ValueError(f"Unreasonable age value: {age_in_days} days")
                                    
                            except (ValueError, TypeError) as e:
                                print(f"Error processing session age: {e}")
                                raise

                        elif 'PatientAge' in dicom_header.info:
                            print("No DOB in dicom header or age in session info! Trying PatientAge from dicom...")
                            try:
                                age = dicom_header.info['PatientAge']
                                if not age:
                                    raise ValueError("PatientAge is empty")
                                    
                                if age.endswith('M'):
                                    # Remove leading zeros and 'M', then convert to int
                                    age_in_months = int(age.rstrip('M').lstrip('0'))
                                    if age_in_months == 0:
                                        raise ValueError("Age cannot be 0 months")
                                    age_in_days = int(age_in_months * 30.44)
                                else:
                                    # Original case for days ('D')
                                    age = re.sub('\D', '', age)
                                    age_in_days = int(age)
                                    age_in_months = int(age_in_days / 30.44)
                                    
                                # Sanity check
                                if age_in_days < 0 or age_in_days > 36500:
                                    raise ValueError(f"Unreasonable age value: {age_in_days} days")
                                    
                            except (ValueError, TypeError) as e:
                                print(f"Error processing DICOM age: {e}")
                                raise
                        else:
                            print("No age at scan in session info label! Ask PI...")
                            raise ValueError("No valid age information found")
    
    age_in_months = str(age_in_months) + "M"
    # assign values to lists. 
    data = [{'subject': subject_label, 'session': session_label, 'dicom_age_in_months': age_in_months, 'sex': PatientSex, 'acquisition': cleaned_string }]  
    # Creates DataFrame.  
    demo = pd.DataFrame(data)
    print("Demographics: ", subject_label, session_label, age_in_months, PatientSex)

    return demo

    # -------------------  Concatenate the data  -------------------  #

def housekeeping(demo):

    cleaned_string = demo['acquisition'].values[0]
    filePath = '/flywheel/v0/work/All_volumes.csv'
    volumes = pd.read_csv(filePath, sep='\s+', index_col=False, engine='python')
    df = pd.concat([demo.reset_index(drop=True), volumes.reset_index(drop=True)], axis=1)
    out_name = f"{cleaned_string}_volumes.csv"
    outdir = ('/flywheel/v0/output/' + out_name)
    df.to_csv(outdir, index=False)

