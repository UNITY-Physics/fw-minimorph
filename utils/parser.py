"""Parser module to parse gear config.json."""

from typing import Tuple
from flywheel_gear_toolkit import GearToolkitContext
# from utils.curate_output import demo
import sys
import os

from shared.utils.curate_output import demo
import warnings


import logging


log = logging.getLogger(__name__)

def parse_config(
    gear_context: GearToolkitContext,
     
) -> Tuple[str, str]: # Add dict for each set of outputs
    """Parse the config and other options from the context, both gear and app options.

    Returns:
        gear_inputs
        gear_options: options for the gear
        app_options: options to pass to the app
    """
    # Gather demographic data from the session
    log.info("Pulling demographics...")
    demographics = demo(gear_context)

    log.info("Running parse_config...")

    input = gear_context.get_input_path("input")
    age_template = gear_context.config.get("age")
   
    if age_template == "None" or age_template is None:
        log.warning("Age is not provided in the config.json file. Checking for age in dicom headers...")
        age_demo = demographics['age'].values[0]
        log.info(f"Age from demographics:  {age_demo}")
        #age_demo = age_demo.replace('M', '') 
        try:
            age_demo = float(age_demo)
            print(age_demo, type(age_demo))
            if age_demo < 5:
                age_template = '3M'
            elif age_demo < 10:
                age_template = '6M'
            elif age_demo < 16:
                age_template = '12M'       
            elif age_demo < 22:
                age_template = '18M'        
            elif age_demo < 30:
                age_template = '24M'
            else:
                age_template = None
                ValueError("Age is not provided in config.json file or dicom headers")

        except ValueError as ve:
            print(f"Caught a ValueError: {ve}")
        except TypeError as te:
            print(f"Caught a TypeError: {te}")
        except Exception as e:
            print(f"Caught a general exception: {e}")
    
            
    print("Age template is: ", age_template)
    return input, age_template, demographics
