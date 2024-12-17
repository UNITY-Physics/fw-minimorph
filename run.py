#!/usr/bin/env python
"""The run script."""
import logging
import os

# import flywheel functions
from flywheel_gear_toolkit import GearToolkitContext
from utils.parser import parse_config
from utils.command_line import exec_command
from utils.curate_output import housekeeping
from utils.Inspect_segmentations import SegQC

# from utils.parseOutput import parseOutput

# The gear is split up into 2 main components. The run.py file which is executed
# when the container runs. The run.py file then imports the rest of the gear as a
# module.

log = logging.getLogger(__name__)

def main(context: GearToolkitContext) -> None:
    """Parses config and runs."""
    input_path, age, demographics = parse_config(context)
    
    print("running main.sh...")
    # Set the command to be executed
    command = "/flywheel/v0/app/main.sh"
    # Add the input path and age to the command
    command = f"{command} {input_path} {age}"
    # Execute the command
    exec_command(command, shell=True, cont_output=True)

    # Run housekeeping
    print("running housekeeping...")
    housekeeping(demographics)

    # Run Segmentation QC
    print("running segmentation QC...")
    subject_label = demographics['subject'].values[0]
    SegQC(input_path, subject_label)

# Only execute if file is run as main, not when imported by another module
if __name__ == "__main__":  # pragma: no cover
    # Get access to gear config, inputs, and sdk client if enabled.
    with GearToolkitContext() as gear_context:

        # Initialize logging, set logging level based on `debug` configuration
        # key in gear config.
        gear_context.init_logging()

        # Pass the gear context into main function defined above.
        main(gear_context)