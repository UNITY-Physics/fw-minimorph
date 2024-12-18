# Changelog

18/12/2024
Version 1.0.1
- template_age added to the output csv
- Missing column headers added to the output csv

17/12/2024
Version 1.0.0
- Cleaned working version of the script

16/12/2024
Version 0.5.2
- Included new templates
- main.sh updated paths for outuput csv
- housekeeping removed column index
- Updating functioning - still need to cleanup output naming

09/07/2024
Version 0.1.7
- Functioning version of the script, with cleaned up outputs and comments
- Requires testing on Flywheel & sanity checks
- Note: feature requests for additional tissue classes

## 0.1.3
```
NJB: 23/04/2024
- Added catch if age is not provided
- ls path permissions to debug work dir issue
```

## 0.0.9
```
NJB: 23/04/2024
- Added in volume calculations
- Added in slicer for visualisation

NOTE: Pushes everything to output directory for now since there seems to be an issue with work directory. 

```
## 0.0.2
```
NJB: 19/04/2024
- Refactored the main script for a gear to be used in Flywheel
- Added in comments and documentation for the script
- Included parsing of the input and output files

**Note**: Deployed in Flywheel for testing

```

## 0.0.1
```
NJB: 18/04/2024
Initial release of the Docker image for Flywheel
- Check dependencies and set up template for future development
```

## 0.0.0
```
NJB: 17/04/2024

- Initial build of Docker image including full builds of
    - FreeSurfer 7.4.1
    - FSL 6.0.4
    - ANTs 2.4.0
    - C3D 1.1.0

```