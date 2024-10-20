# ANTs Tissue Segmentation

## Overview

This script is designed to run the ANTs pipeline for segmenting infant brain images on Flywheel. The pipeline consists of the following steps:
1. Register segmentation priors (tissue and CSF) and segmentation masks (ventricles, subcortical GM and collosal segments) to native space via an age-specific template
2. Segment the input image in template space using ANTs Atropos and fsl

The script assumes that the input image is in NIfTI format. The script outputs the segmentations in native space.

**Computation of Age-Specific Templates, Segmentation Priors and Segmentation Masks:**

<u>i)Age-specific templates:</u> The templates used in this pipeline were constructed using a subset of high-quality datasets from the UCT-Khula study. Brain extraction was performed on the isotropic T2-weighted images using the mri_synthstrip tool. Edge images were generated using FSL. Both the brain-extracted and edge images were used as input channels for template building in antsMultivariateTemplateConstruction.sh.

ii) Segmentation priors: 
To generate tissue and CSF priors, age-specific T2-weighted images and corresponding tissue segmentation maps from the Baby Connectome Project (BCP) atlas were non-linearly registered to the age-specific study template using ANTs. These transformations were applied to the white matter (WM), grey matter (GM), and cerebrospinal fluid (CSF) segmentation maps.
- Tissue prior: The WM and GM priors were summed to generate a combined "tissue" prior.
- Skull prior: A "skull" prior was created by dilating the brain mask and subtracting the original mask, isolating the skull boundary. Note: this skull prior is used exclusively to improve the quality of extra-axial segmentations and should not be used for volumetric analysis.

iii) Segmentation masks:
- Subcortical GM segmentation masks: The age-specific template was resampled to a 0.5mm isotropic resolution, and the subcortical parcellation maps from the BCP atlas were registered to this template.
- Callosal masks: The age-specific template was resampled to a 1mm isotropic resolution, and the Penn-CHOP Infant Brain Atlas (1-year-old) was registered to it.
- Ventricles masks: Ventricles were manually delineated in template space, and their accuracy was confirmed through visual inspection by a second expert.

**Segmentation pipeline:**

Native, brain-extracted T2-w isotropic files are registered to the age-specific template using ANTs’ SyN registration. The resulting transformations are then applied to the CSF, tissue and skull priors. Subsequently, antsAtroposN4.sh is used to segment the native image into three tissue classes, using a dilated brain mask, with a priors’ weight of 0.3. The resulting tissue segmentation posteriors are refined to separate the ventricles from other cerebrospinal fluid (CSF) regions. To obtain the subcortical GM  and callosal segmentations, the tissue posterior obtained with ANTs is multiplied by the subcortical GM and callosum masks in native space. 

[Usage](#usage)

This script is designed to be run as a Flywheel Gear. The script takes two inputs:
1. The input image to segment
2. The age of the template to use in months (e.g. 3, 6, 12, 24)


[FAQ](#faq)

### Summary


### Cite

**license:**


**url:** <https://gitlab.com/flywheel-io/flywheel-apps/>

**cite:**  
Fast and sequence-adaptive whole-brain segmentation using parametric Bayesian modeling. O. Puonti, J.E. Iglesias, K. Van Leemput. NeuroImage, 143, 235-249, 2016.

### Classification

*Category:* analysis

*Gear Level:*

* [ ] Project
* [x] Subject
* [x] Session
* [ ] Acquisition
* [ ] Analysis

----

### Inputs

* api-key
  * **Name**: api-key
  * **Type**: object
  * **Optional**: true
  * **Classification**: api-key
  * **Description**: Flywheel API key.

### Config

* Age
  * **Name**: age
  * **Type**: string
  * **Description**: age in months of the template to use
  * **Default**: None

* input
  * **Base**: file
  * **Description**: input file (usually isotropic reconstruction)
  * **Optional**: false

### Outputs
* output
  * **Base**: file
  * **Description**: segmentated file 
  * **Optional**: false

* parcelation
  * **Base**: file
  * **Description**: parcelation nifti files for visual QC
  * **Optional**: true

* volume
  * **Base**: file
  * **Description**: volume estimation file (csv)
  * **Optional**: true

#### Metadata

No metadata currently created by this gear

### Pre-requisites

- Three dimensional structural image

#### Prerequisite Gear Runs

This gear runs on BIDS-organized data. To have your data BIDS-ified, it is recommended
that you run, in the following order:

1. ***dcm2niix***
    * Level: Any
2. ***file-metadata-importer***
    * Level: Any
3. ***file-classifier***
    * Level: Any

#### Prerequisite

## Usage

This section provides a more detailed description of the gear, including not just WHAT
it does, but HOW it works in flywheel

### Description

This gear is run at either the `Subject` or the `Session` level. It downloads the data
for that subject/session into the `/flwyhweel/v0/work/` folder and then runs the
`ants-segmentation` pipeline on it.

After the pipeline is run, the output folder is zipped and saved into the analysis
container.

#### File Specifications

This section contains specifications on any input files that the gear may need

### Workflow

A picture and description of the workflow

```mermaid
  graph LR;
    A[T1w]:::input --> FW;
    FW[FW] --> FMI;
    FMI((file-metadata-importer)):::gear --> FC;
    FC((file-classifier)):::gear --> D2N;
    D2N((dcm2niix)):::gear --> MRR;
    MRR((mrr)):::gear --> ANA;
    ANA[Analysis]:::container;
    
    classDef container fill:#57d,color:#fff
    classDef input fill:#7a9,color:#fff
    classDef gear fill:#659,color:#fff
```

Description of workflow

1. Upload data to container
2. Prepare data by running the following gears:
   1. file metadata importer
   2. file classifier
   3. dcm2niix
3. Select either a subject or a session.
4. Run the MRR gear (Hyperfine multi-resolution registration)
5. Run the ants-segmentation gear

### Use Cases

## FAQ

[FAQ.md](FAQ.md)

## Contributing

[For more information about how to get started contributing to that gear,
checkout [CONTRIBUTING.md](CONTRIBUTING.md).]
