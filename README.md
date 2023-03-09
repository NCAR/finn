# FINN

FINN (Fire INventory from NCAR) Preprocessor and Emission Estimator

As of 2023-03-07, master branch is being reorganized for v2.5 release.

Latest stable version is [v2.4](https://github.com/NCAR/finn-preprocessor/releases/tag/finn2.4-preproc1.3)

Documentation for preprocessor [here README_preprocessor.md](https://github.com/NCAR/finn-preprocessor/blob/master/README_preprocessor.md)

Emission estimator is in [v2.5_emissions_code](https://github.com/NCAR/finn-preprocessor/tree/master/v2.5_emissions_code)

The process for calculating emissions with FINN is to first run the preprocessor, which combines nearby fire detections into fire regions from MODIS and VIIRS observations, and writes a file containing the location, area, vegetation type, etc., for each fire.  Second, the IDL emissions code is run, which estimates the biomass burned for each fire, and applies emission factors for each fire based on vegetation type to calculate the base species (BC, OC, CO, NOx, NMVOC, etc.), and then the total NMVOC is speciated into individual VOCs for MOZART, SAPRC99 and GEOS-Chem chemical mechanisms.

