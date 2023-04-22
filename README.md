# FINN

FINN (Fire INventory from NCAR) Preprocessor and Emission Estimator

As of 2023-04-21, code is at github: https://github.com/NCAR/finn

Latest stable version is [v2.4](https://github.com/NCAR/finn/releases/tag/finn2.4-preproc1.3)

Documentation for preprocessor [here README_preprocessor.md](https://github.com/NCAR/finn/blob/master/README_preprocessor.md)

Emission estimator is in [v2.5_emissions_code](https://github.com/NCAR/finn/tree/master/v2.5_emissions_code)

The process for calculating emissions with FINN is to first run the preprocessor, which combines nearby fire detections into fire regions from MODIS and VIIRS observations, and writes a file containing the location, area, vegetation type, etc., for each fire.  Second, the IDL emissions code is run, which estimates the biomass burned for each fire, and applies emission factors for each fire based on vegetation type to calculate the base species (BC, OC, CO, NOx, NMVOC, etc.), and then the total NMVOC is speciated into individual VOCs for MOZART, SAPRC99 and GEOS-Chem chemical mechanisms.

Please see Wiedinmyer et al. (2023) for more information: https://egusphere.copernicus.org/preprints/2023/egusphere-2023-124/
