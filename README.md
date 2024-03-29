# FINN (Fire INventory from NCAR) Preprocessor and Emission Estimator

Fire Inventory from NCAR (FINN), a fire emissions inventory that provides publicly available emissions of trace gases and aerosols.

Latest stable version is v2.5.2, available from [Zenodo](https://doi.org/10.5281/zenodo.7854306) or [GitHub](https://github.com/NCAR/finn/releases/tag/finn2.5.2)

The process for calculating emissions with FINN is to first run the preprocessor, which combines nearby fire detections into fire regions from MODIS and VIIRS observations, and writes a file containing the location, area, vegetation type, etc., for each fire.  Second, the IDL emissions code is run, which estimates the biomass burned for each fire, and applies emission factors for each fire based on vegetation type to calculate the base species (BC, OC, CO, NOx, NMVOC, etc.), and then the total NMVOC is speciated into individual VOCs for MOZART, SAPRC99 and GEOS-Chem chemical mechanisms.

Please see Wiedinmyer et al. (2023) for more information: https://gmd.copernicus.org/articles/16/3873/2023/

Documentation for GIS Preprocessor is [README_preprocessor.md](https://github.com/NCAR/finn/blob/master/README_preprocessor.md)

Documentation for Emission estimator is [README_emissions.md](https://github.com/NCAR/finn/tree/master/README_emissions.md)

Code repository is at github: https://github.com/NCAR/finn
