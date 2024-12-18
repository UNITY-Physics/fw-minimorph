import os
import re

directory_path = '/Users/nbourke/GD/atom/unity/fw-gears/fw-minimorph/utils/tests/input'

for filename in os.listdir(directory_path):
    if os.path.isfile(os.path.join(directory_path, filename)):
        filename_without_extension = filename.split('.')[0]
        no_white_spaces = filename_without_extension.replace(" ", "")
        # Exclude "-" from being replaced
        cleaned_string = re.sub(r'[^a-zA-Z0-9-]', '_', no_white_spaces)
        cleaned_string = cleaned_string.rstrip('_')  # Remove trailing underscore
        print(cleaned_string)  # For testing purposes