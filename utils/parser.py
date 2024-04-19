"""Parser module to parse gear config.json."""

from typing import Tuple
from flywheel_gear_toolkit import GearToolkitContext

def parse_config(
    gear_context: GearToolkitContext,
     
) -> Tuple[str, str]: # Add dict for each set of outputs
    """Parse the config and other options from the context, both gear and app options.

    Returns:
        gear_inputs
        gear_options: options for the gear
        app_options: options to pass to the app
    """

    print("Running parse_config...")

    input = gear_context.get_input_path("input")
    age = gear_context.config.get("age")

    if age is None:
        raise ValueError("Template is required")
    # TO DO: Add in parser to look for age where possible

    return input, age
