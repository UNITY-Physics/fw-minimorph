"""Parser module to parse gear config.json."""

from typing import Tuple
from flywheel_gear_toolkit import GearToolkitContext
from utils.curate_output import demo
import warnings

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
    print("pulling demographics...")
    demographics = demo(gear_context)

    print("Running parse_config...")

    input = gear_context.get_input_path("input")
    age = gear_context.config.get("age")

    if age is None:
        warnings.warn("WARNING!!! Age is not provided in the config.json file", UserWarning)
        print("Checking for age in dicom headers...")
        age = demographics['dicom_age_in_months'].values[0]
        print("dicom_age_in_months: ", age)
    else:
        ValueError("Age is not provided in config.json file or dicom headers")

    return input, age, demographics
