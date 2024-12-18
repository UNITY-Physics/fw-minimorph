import os
import numpy as np
import nibabel as nib
from PIL import Image, ImageDraw, ImageFont
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import sys
import glob

def SegQC(input_image_path, subj):

    # Setup the output directory
    overlay_dir = '/flywheel/v0/output'  # Directory to save overlay images
    # Create overlay directory if it doesn't exist
    os.makedirs(overlay_dir, exist_ok=True)

    # Dictionary to store paths of generated GIF images
    gif_images = {}  # Key: subject, Value: dict of plane: gif path

    print(f'Processing {subj}...')
    # # Path to output image
    # atlas_image_path = os.path.join('/flywheel/v0/output/Segmentation_atlas_all_classes.nii.gz')  # T1


    # Find all files that end with '_segmentation.nii.gz'
    atlas_image_path = glob.glob(os.path.join(overlay_dir, '*_segmentation.nii.gz'))
    # Take the first file
    atlas_image_path = atlas_image_path[0]


    # Load images
    if not os.path.exists(input_image_path) or not os.path.exists(atlas_image_path):
        print(f"Images not found for {subj}. Skipping.")
        sys.exit(0)  # Exit the entire script with status code 0 (successful exit)

    registered_img = nib.load(input_image_path)
    reference_img = nib.load(atlas_image_path)

    # Get data arrays
    registered_data = registered_img.get_fdata()
    reference_data = reference_img.get_fdata()

    # Define the planes and corresponding slice indices
    planes = ['axial', 'coronal', 'sagittal']
    slices_indices = {
        'axial': registered_data.shape[2] // 2,
        'coronal': registered_data.shape[1] // 2,
        'sagittal': registered_data.shape[0] // 2
    }

    # Dictionary to store GIF paths for this subject
    subject_gif_paths = {}

    for plane in planes:
        slice_index = slices_indices[plane]

        # Extract slices based on the plane
        if plane == 'axial':
            registered_slice = registered_data[:, :, slice_index]
            reference_slice = reference_data[:, :, slice_index]
        elif plane == 'coronal':
            registered_slice = registered_data[:, slice_index, :]
            reference_slice = reference_data[:, slice_index, :]
            # Rotate for correct orientation
            registered_slice = np.rot90(registered_slice)
            reference_slice = np.rot90(reference_slice)
        elif plane == 'sagittal':
            registered_slice = registered_data[slice_index, :, :]
            reference_slice = reference_data[slice_index, :, :]
            # Rotate for correct orientation
            registered_slice = np.rot90(registered_slice)
            reference_slice = np.rot90(reference_slice)

        # Normalize the registered image for display (grayscale)
        registered_slice_norm = (registered_slice - np.min(registered_slice)) / (np.max(registered_slice) - np.min(registered_slice) + 1e-8)
        registered_image_uint8 = (registered_slice_norm * 255).astype(np.uint8)
        registered_image = Image.fromarray(registered_image_uint8).convert('L')

        # Apply a colormap to the atlas labels (0 to 30)
        colormap = cm.get_cmap('jet', 31)  # Use a colormap with 31 discrete colors (0-30)
        reference_slice_colormap = colormap(reference_slice / 30.0)  # Normalize between 0 and 1

        # Convert the colormapped atlas slice to an 8-bit image (RGB)
        reference_image_colored = (reference_slice_colormap[:, :, :3] * 255).astype(np.uint8)
        reference_image = Image.fromarray(reference_image_colored)

        # Resize images to a standard size
        registered_image = registered_image.resize((256, 256))
        reference_image = reference_image.resize((256, 256))

        # Function to add text below image
        def add_text(image, subj_name, plane_name):
            # Increase image height to add space for the text
            new_height = image.height + 30  # Add 30 pixels at the bottom
            new_image = Image.new('RGB', (image.width, new_height), color=(0, 0, 0))  # 'RGB' mode for color

            # Paste the image onto the new image
            new_image.paste(image, (0, 0))

            # Draw the text
            draw = ImageDraw.Draw(new_image)
            text = f'{plane_name.capitalize()}'
            font = ImageFont.load_default()  # Use default font

            # Calculate text width and position using textbbox
            text_bbox = draw.textbbox((0, 0), text, font=font)
            text_width = text_bbox[2] - text_bbox[0]  # Width of the text
            text_height = text_bbox[3] - text_bbox[1]  # Height of the text

            text_x = (new_image.width - text_width) // 2
            text_y = image.height + (30 - text_height) // 2  # Center the text vertically

            # Add text
            draw.text((text_x, text_y), text, font=font, fill=(255, 255, 255))  # White text

            return new_image

        # Add plane name to images
        registered_image = add_text(registered_image, subj, plane)
        reference_image = add_text(reference_image, subj, plane)

        # Create an animated GIF for this plane
        frames = [reference_image.convert('RGB'), registered_image.convert('RGB')]

        gif_image_path = os.path.join(overlay_dir, f'sub-{subj}_{plane}.gif')

        # Save frames as an animated GIF
        frames[0].save(gif_image_path, format='GIF', append_images=frames[1:], save_all=True, duration=500, loop=0)

        subject_gif_paths[plane] = gif_image_path

    # Store the GIF paths for this subject
    gif_images[subj] = subject_gif_paths

    print('All animated GIFs have been created.')

    # Optionally, create an HTML file to view all GIFs together in rows
    html_output_path = os.path.join('/flywheel/v0/output/registration_check.html')
    with open(html_output_path, 'w') as f:
        f.write('<html><body>\n')
        f.write('<style>table {border-collapse: collapse;} td {padding: 5px;}</style>\n')
        f.write('<table>\n')
        # for subj, planes_dict in gif_images.items():
        f.write('<tr>\n')
        f.write(f'<td colspan="3" style="text-align:center;"><h2>{subj}</h2></td>\n')
        f.write('</tr>\n')
        f.write('<tr>\n')
        for plane in ['axial', 'coronal', 'sagittal']:
                f.write(f'<td style="text-align:center;">\n')
                f.write(f'<img src="./sub-{subj}_{plane}.gif" alt="{subj} {plane}"><br>\n')
                f.write(f'<b>{plane.capitalize()}</b>\n')
                f.write('</td>\n')
        f.write('</tr>\n')
        f.write('<tr><td colspan="3"><hr></td></tr>\n')
        f.write('</table>\n')
        f.write('</body></html>')

    print('HTML file has been created to view all GIFs together.')
