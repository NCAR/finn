; ; ***********UPDATE TO v2.0****************************************
; MARCH 05-11, 2015
; (NOTE: UPDATES by Christine denoted in code by "cw")
; - This is the file sent to me from YO (in email dated 11/27/2014)
;    ** The file is called "global_fire_v15_txprj.pro"
;    ** renaming it today "global_fire_v2_txprj.pro"
; - Got rid of the removal of files with confidence < 20 (This will already be taken care of in input processing)
; - Added area to the input file and all further
; - Removed Jay's code to remove overlapping fires
; - Included a field for the esa_cci value to be read in
; - Updated the format of the input file: 
;   ** Removed State, Time, TPIX/SPIX from the inputs read in and processed
; - Changed the extent of the tropical region from 30 degrees to 23.5 degrees (consistent with what YO had)
; - included polyid and fireid in output file
;
; APRIL 15-22, 2015
; - Corrected the ESA Scenario (which had a problem with the urban/bare areas)
; - removed doubling over tropical regions (taken care of in the new FINN GIS pre-processor)
; - Removed the fraction of bare from area burned estimate
; - in the TCEQ and FCCS data to which genveg --> 0, changed to new land cover depending on tree/herb cover
;   (see notes in scenarios) 
;
; MAY 29, 2015
; - edited the input file header to match the input file I made on 05222015 (SUBDIVIDED FILE) 
; - Edited areanow so that the grass and crop are scaled by 0.75 (as in FINNv1)
; - Checked emission factors (updated EF input file)
; - Ran with new input file (NO GLC INCLUDED)
; 
; JUNE 01, 2015
; - added back in GLC and a new field for state
; - edited input/output file to have state included
; 
; June 03, 2015
; - corrected TCEQ fuel load input csv file (assigned crops genveg = 9)
; - redo all runs
; 
; FEBRUARY 04-08, 2019
; - renamed global_fire_v2_TXprj_yk to global_fire_v2_02042019
; - Corrected to include 2016 and 2020 as leap year
; - gor rid of different scenarios - only have scen1 = LCT
; - Confirmed: tropics here and in preprocessor are from -23.5 to 23.5
; - Deleted a bunch of loops for the different scenarios and commented-out code to clean up
; - New EF and Fuel Load questions
; - For North America, included updated tree and herb fuel loadings that were created as part of earlier TX project
; - Added back in NO and NO2 into output file
; - Checked units of parameters and emissions calculations
; - Scaled area burned - to vegetated fraction (remove bare) [NOTE: This was not in the earlier TX code. Don't know why]
; - Removed the scaling of area burned for crops/grass (it was set to 0.75 in earlier code. Removed in this version)

; FEBRUARY 22, 2019
;- renamed global_fire_v2_02222019
; -removed a lot of junk commented code
; 
; March 12, 2019
; - Running the 2012 regional files
; - Make sure check the input date format!!
; 
; March 17, 2019
; - Yo reran the input files for a larger domain. I have to rerun this code. 
; 
; ***********************************************************************************************************************

pro x_global_fire_v2_02222019_yk3 , infile, simid, yearnum, input_lct, todaydate

; ##################################################################################
; USER INPUTS --- EDIT DATE AND SCENARIO HERE - this is for file naming purposes
; ##################################################################################
; NOTE: ONLY LCT - Don't really need this
scen = 1

;simid  = 'modvrs_na_2012'
;todaydate = '03172019' ; this is for naming the output file
;yearnum= 2012

;infile = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc\work_modvrs_na_2012\out_modvrs_na_2012_modlct_2012_modvcf_2012_regnum.csv' ; 2012 MODIS/VIIRS regional file 3/16/2019
;infile = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc\work_mod_na_2012\out_mod_na_2012_modlct_2012_modvcf_2012_regnum.csv' ; 2012 MODIS regional file created 3/16/2019

inpdir = 'D:\Data2\wildfire\TEXAS\New_2018\emissions_code_yk\code_yk_201905\Inputs'
outdir = 'D:\Data2\wildfire\TEXAS\New_2018\emissions_code_yk\code_yk_201905\Outputs'

close, /all

 t0 = systime(1) ;Procedure start time in seconds

 ; read input option for how to treate flct
 if strmatch(input_lct, 'maj*', /fold_case) then acknowledge_flct = BOOLEAN(0) else $
 if strmatch(input_lct, 'all*', /fold_case) then acknowledge_flct = BOOLEAN(1) else $
 begin
   print,'unknwon "input_lct"', input_lct
   print,'valid values are "majority" or "all"'
   print,'  "majority" assumes that input has record for only majority LCT (traditional FINN approach)'
   print,'  "all" assumes that input has flct which has fractional land cover, and all of LCT for each polygons are exported'
   print,'pass appropriate option and rerun the code!
   stop
 endelse
 
 
    

; ##########################################################################
; SETTING UP VARIABLES To CHECK TOTALS AT THE END OF The FILE

; Calculating the total biomass burned in each genveg for output file 
 TOTTROP = 0.0
 TOTTEMP = 0.0
 TOTBOR = 0.0
 TOTSHRUB = 0.0
 TOTCROP = 0.0
 TOTGRAS = 0.0
; Calculating total area in each genveg for output log file
 TOTTROParea = 0.0
 TOTTEMParea = 0.0
 TOTBORarea = 0.0
 TOTSHRUBarea = 0.0
 TOTCROParea = 0.0
 TOTGRASarea = 0.0
; CALCULATING TOTAL CO and PM2.5 for crops
 TOTCROPCO = 0.0
 TOTCROPPM25 = 0.0

; ****************************************************************************
; ASSIGN FUEL LOADS, EMISSION FACTORS FOR GENERIC LAND COVERS AND REGIONS
; ****************************************************************************
;
; FUEL LOADING FILES
;  02/04/2019 - removed texas code for this section and pasted in old code from v1.5 -- going back to global fuel loadings
;  READ IN FUEL LOADING FILE
;  02/08/2019: ALL FUEL INPUTS ARE IN g/m2

    fuelin = inpdir + '\Fuel_LOADS_NEW_022019.csv' ; 
;    infuel=ascii_template(fuelin)
;    fuel=read_ascii(fuelin, template=infuel)
    fuel=read_csv(fuelin)

;   Set up fuel arrays
       globreg2 = fuel.field1
       tffuel = fuel.field2  ;tropical forest fuels
       tefuel = fuel.field3  ;temperate forest fuels
       bffuel = fuel.field4  ;boreal forest fuels
       wsfuel = fuel.field5  ;woody savanna fuels
       grfuel = fuel.field6  ;grassland and savanna fuels
       ; NOTE: Fuels read in have units of g/m2 DM
 
; 02/08/2019
; READ in LCT Fuel loading file from prior Texas FINN study
; This is a secondary fuel loading file for use in US ONLY
  lctfuelin = inpdir + '\LCTFuelLoad_fuel4_revisit20190521.csv'
;  infuelLCT=ascii_template(LCTfuelin)
;  LCTfuel=read_ascii(LCTfuelin, template=infuelLCT)
  LCTfuel=read_csv(LCTfuelin)
;  
  lctfuelid = lctfuel.field1
  lcttree = lctfuel.field2
  lctherb = lctfuel.field3

; EMISSION FACTOR FILE
; READ IN EMISSION FACTOR FILE
    emisin = inpdir + '\Updated_EFs_02042019.csv' ; NEW FILE created and Added on 02/08/2019
;    inemis=ascii_template(emisin)
;    emis=read_ascii(emisin, template=inemis)
    emis=read_csv(emisin, template=inemis)

;   Set up Emission Factor Arrays
;  1     2            3            4  5   6   7     8    9      10  11    12  13  14  15  16  17  18  19    20
; LCT GenVegType  GenVegDescript  CO2 CO  CH4 NMOC  H2  NOXasNO SO2 PM25  TPM TPC OC  BC  NH3 NO  NO2 NMHC  PM10
       lctemis = emis.field01   ; LCT Type (Added 10/20/2009)
       vegemis = emis.field02   ; generic vegetation type --> this is ignored in model
       CO2EF = emis.field04     ; CO2 emission factor
       COEF = emis.field05     ; CO emission factor
       CH4EF = emis.field06     ; CH4 emission factor
       NMHCEF = emis.field19    ; NMHC emission factor
       NMOCEF = emis.field07    ; NMOC emission factor (added 10/20/2009)
       H2EF = emis.field08      ; H2 emission factor
       NOXEF = emis.field09     ; NOx emission factor
       NOEF = emis.field17      ; NO emission factors (added 10/20/2009)
       NO2EF = emis.field18     ; NO2 emission factors (added 10/20/2009)
       SO2EF = emis.field10     ; SO2 emission factor
       PM25EF = emis.field11    ; PM2.5 emission factor
       TPMEF = emis.field12     ; TPM emission factor
       TCEF = emis.field13      ; TPC emission factor
       OCEF = emis.field14      ; OC emission factor
       BCEF = emis.field15      ; BC emission factor
       NH3EF = emis.field16     ; NH3 emission factor
       PM10EF = emis.field20    ; PM10 emission factor (added 08/18/2010)
  
print, "Finished reading in fuel and emission factor files"

; ****************************************************************************
; SEt UP OUTPUT FILES
; ****************************************************************************
; yk_undo:  file/path
;    outfile = 'E:\Data2\wildfire\TEXAS\NEW_PROJECT_2014\FINNv2\RUN_MAY2015\OUTPUT\FINNv2_'+ scename+'_'+ simid + '_'+ todaydate+'.txt'
     outfile = outdir + '\' + simid + '_'+todaydate+'.txt'
          openw, 6, outfile
     print, 'opened output file: ', outfile

; CW REWROTE OUTPUT FORMAT, 02/04/2019
       printf, 6, 'longi,lat,polyid,fireid,jd,lct,genLC,pcttree,pctherb,pctbare,area,bmass,CO,NOx,NO,NO2,NH3,SO2,NMOC,PM25,PM10,OC,BC' 
       form = '(D20.10,",",D20.10,",",(5(I10,",")),16(D25.10,","))'


; CREATE AND OPEN A LOG FILE to go with output file
    logfile = outdir + '\LOG_' + simid + '_'+todaydate+'.txt'
    openw, 9, logfile
    print, 'SET UP OUTPUT FILES'

;***************************************************************************************
; READIN IN FIRE AND LAND COVER INPUT FILE (CREATED WITH PREPROCESSOR)
; **************************************************************************************

;infile ='D:\Data2\wildfire\TEXAS\New_2018\EMISSIONS_CODE\INPUT_FILES\Input_preprocessed\out_CW_TEST_modlct_2017_modvcf_2017_regnum_testtiny.csv'
;infile = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc\work_mod_na_2012\out_mod_na_2012_modlct_2012_modvcf_2012_regnum.csv' ; 2012 MODIS only regional file
;infile = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc\work_modvrs_na_2012\out_modvrs_na_2012_modlct_2012_modvcf_2012_regnum.csv' ; 2012 MODIS/VIIRS regional file
  
; Read in FIRE FILE
; SKIP FIRST LINE WITH LABELS
;       intemp=ascii_template(infile)
;        map=read_ascii(infile, template=intemp)
        map=read_csv(infile)
        

; Get the number of fires in the file
        nfires = n_elements(map.field01)
    		print, 'Finished reading input file'

; NEW FILE AS OF 02/04/2019
       ; 1       2       3      4       5           6        7      8      9     10     11     12
       ;polyid,fireid,cen_lon,cen_lat,acq_date_lst,area_sqkm,v_lct,f_lct,v_tree,v_herb,v_bare,v_regnum
       ;polyid,fireid,cen_lon,cen_lat,acq_date_lst,area_sqkm,v_lct,f_lct,v_tree,v_herb,v_bare,v_regnum
       ; 1,2,-105.798745979379,23.1082043552665,2011-12-30,1.07388108003883,10,0.485714285714286,11.7428571428571,74.1428571428571,14.8,2


        polyid1 = map.field01
        fireid1 = map.field02
        
        lat1 = map.field04
        lon1 = map.field03
        date1 = map.field05
        area1 = map.field06 ; CW: Added March 05, 2015  -- NEED set the field
 
        tree1 = map.field09*1.0
        herb1 = map.field10*1.0
        bare1 = map.field11*1.0
 
        lct1 = map.field07 
        flct1 = map.field08
        
        globreg=map.field12
        
; Total Number of fires input in original input file
      numorig = n_elements(lct1)
		
Print, 'The total number of fires in is: ', numorig
print, 'Finished Reading Input file'

; Added 08/25/08: removed values of -9999 from VCF inputs
	misstree = where(tree1 lt 0)
	if misstree[0] ge 0 then tree1(misstree) = 0.0
	missherb = where(herb1 lt 0)
	if missherb[0] ge 0 then herb1(missherb) = 0.0
	missbare = where(bare1 lt 0)
	if missbare[0] ge 0 then bare1(missbare) = 0.0

; Calculate the total cover from the VCF product (CHECK TO MAKE SURE PERCENTAGES ADD TO 100%)
        totcov = tree1+herb1+bare1
        missvcf = where(totcov lt 98.)
  	    if missvcf[0] eq -1 then nummissvcf =0 else nummissvcf = n_elements(missvcf)

; ***************************************************************************************
; JULIAN DATE: Calculate the julian day for the fire detections
       numfire1 = numorig
       jd2 = intarr(numfire1)

; yk: save month for diagnosis
       mo2 = intarr(numfire1)
       dy2 = intarr(numfire1)
       yr2 = intarr(numfire1)
       
;!!!!!!!!!!! EDIT THIS SECTION FOR THE CORRECT DATE FORMAT!!!
; For dates with the format: 3/1/2007
;for i = 0L,numfire1-1 do begin
;         parts =  strsplit(date1[i],'/',/extract)
;         day = fix(parts[1])
;         month = fix(parts[0])
; For Dates with the format:  2013-02-01
For i = 0L,numfire1-1 do begin
    parts =  strsplit(date1[i],'-',/extract) ; ***** EDIT FOR DATE FORMAT!! ********
    year_x = fix(parts[0])
    day = fix(parts[2])
    month = fix(parts[1])
    
    if yearnum mod 4 eq 0 then begin
      ; set julian date (leap year)
      if month eq 1 then daystart = 0
      if month eq 2 then daystart = 31
      if month eq 3 then daystart = 60
      if month eq 4 then daystart = 91
      if month eq 5 then daystart = 121
      if month eq 6 then daystart = 152
      if month eq 7 then daystart = 182
      if month eq 8 then daystart = 213
      if month eq 9 then daystart = 244
      if month eq 10 then daystart = 274
      if month eq 11 then daystart = 305
      if month eq 12 then daystart = 335
      ntotdays = 366
    endif else begin
      ; set julian date (NOT a leap year)
      if month eq 1 then daystart = 0
      if month eq 2 then daystart = 31
      if month eq 3 then daystart = (28+31)
      if month eq 4 then daystart = 90
      if month eq 5 then daystart = 120
      if month eq 6 then daystart = 151
      if month eq 7 then daystart = 181
      if month eq 8 then daystart = 212
      if month eq 9 then daystart = 243
      if month eq 10 then daystart = 273
      if month eq 11 then daystart = 304
      if month eq 12 then daystart = 334
      ntotdays = 365     
    endelse
          jd2[i] = day+daystart

; yk: save month for diagnosis
  yr2[i] = year_x
          mo2[i] = month
          dy2[i] = day
  endfor
  print, 'Finished calculating Julian Dates'
; *******************************************************************************************************************
;THIS SECTION (AND RENAMING OF ARRAYS) WAS A REMNANT FROM OLDER CODE. 
  fireid = [fireid1]
  polyid = [polyid1]
  lat=[lat1]
  lon=[lon1]
  tree=[tree1]
  herb=[herb1]
  bare=[bare1]
  lct=[lct1]
  flct = [flct1]
  jd = [jd2]
; yk: save month for diagnosis
  mo = [mo2]
  dy = [dy2]
  area = [area1]
  yr = [yr2]
  
  ngoodfires = n_elements(jd)

  printf, 9, 'the number of fires (ngoodfires) = ', ngoodfires
  print, 'The number of fires (ngoodfires) = ', ngoodfires 
; *******************************************************************************
; Set up Counters
; These are identifying how many fires are in urban areas,
; or have unidentified VCF or LCT values -->
; purely for statistics and quality assurance purposes
        lct0 = 0L
        spixct = 0L
        antarc = 0L
        allbare = 0L
        genveg0 = 0L
        bmass0 = 0L
        vcfcount = 0L
        vcflt50 = 0L
        confnum = 0L ; added 08/25/08
        overlapct = 0L ; added 02/29/2009
        urbnum = 0L ; added 10/20/2009
        noglobreg = 0L ; Added 03/12/2019 to account for no global region assigned to fire
        yearnogood = 0L

; Sort fires in order of JD
    index2=sort(jd)
    lat=lat[index2]
    lon=lon[index2]

    polyid = polyid[index2]
    fireid = fireid[index2]

    tree=tree[index2]
    herb=herb[index2]
    bare=bare[index2]
    lct=lct[index2]
    flct = flct[index2]
    jd=jd[index2]
    globreg = globreg[index2] ; corrected 03/12/2019
    
; yk: save month for diagnosis
    mo=mo[index2]
    yr = yr[index2]
    totcov = totcov[index2]
    area = area[index2]
    ; yk: for qa, hold onto original land cover values
    lctorig=lct[*]
    
    ; yk: scenuse; actual algorithm being used when falling back to, eg. LCT, for various rasons
    ; CW - 02/04/2019 - don't know what this is?? 
    scenuse=intarr(ngoodfires)
    scenuse[*]=-99
 

; Set totals to 0.0 (FOR OUTPUT LOG FILE)
     COtotal = 0.0
     NMOCtotal = 0.0
     NOXtotal = 0.0
     SO2total = 0.0
     PM25total = 0.0
     OCtotal = 0.0
     BCtotal = 0.0
     NH3total = 0.0
     PM10total = 0.0
     AREAtotal = 0.0 ; added 06/21/2011
     BMASStotal= 0.0 ; Addded 06/21/2011

     
; ****************************************************************************
; START LOOP OVER ALL FIRES: CALCULATE EMISSIONS
; ****************************************************************************
print, 'Starting to Calculate Emissions'

; Start loop over all fires in input file
for j =0L,ngoodfires-1 do begin ; edited this to have ngoodfires instead of nfires on 02.23.2009
  
  if yr[j] ne yearnum then begin
    yearnogood = yearnogood + 1
    goto, skipfire
  endif
  
;
; ##################################################
;   QA PROCEDURES FIRST
; ##################################################
; 1) Correct for VCF product issues
;   1a) First, correct for GIS processing errors:
;    Scale VCF product to sum to 100. (DON'T KNOW IF THIS IS AN ISSUE WITH V2 - BUT LEAVING IN)
        if totcov[j] gt 101. and totcov[j] lt 240. then begin 
           vcfcount = vcfcount+1
           tree[j] = tree[j]*100./totcov[j]
           herb[j] = herb[j]*100./totcov[j]
           bare[j] = bare[j]*100./totcov[j]
           totcov[j] = bare[j] +herb[j] + tree[j]
        endif
        if totcov[j] lt 99. and totcov[j] ge 50. then begin
           vcfcount = vcfcount+1
           tree[j] = tree[j]*100./totcov[j]
           herb[j] = herb[j]*100./totcov[j]
           bare[j] = bare[j]*100./totcov[j]
           totcov[j] = bare[j] +herb[j] + tree[j]
        endif
       ;Second, If no data are assigned to the grid, then scale up, still
        if (totcov[j] lt 50. and totcov[j] ge 1.) then begin
            vcflt50  = vcflt50+1
            tree[j] = tree[j]*100./totcov[j]
            herb[j] = herb[j]*100./totcov[j]
            bare[j] = bare[j]*100./totcov[j]
            totcov[j] = bare[j] +herb[j] + tree[j]
        endif

;   1b) Fires with 100% bare cover or VCF not identified or total cover is 0,-9999:
;    reassign cover values based on LCT assignment
       if totcov[j] ge 240. or totcov[j] lt 1. or bare[j] eq 100 then begin ; this also include where VCF see water (values = 253)
          allbare = allbare+1
          if lct[j] ge 15 then begin
         ; printf, 9, 'Fire number:',j,' removed. either 100% bare of VCF = 253 and LCT = ', lct[j]
          goto, skipfire ; Skip fires that are all bare and have no LCT vegetation
          endif
          if lct[j] le 5 then begin    ; Assign forest to the pixel
            tree[j] = 60.
            herb[j] = 40.
            bare[j] = 0.
          endif
         if lct[j] ge 6 and lct[j] le 8 or lct[j] eq 11 or lct[j] eq 14 then begin    ; Assign woody savanna to the pixel
            tree[j] = 50.
            herb[j] = 50.
            bare[j] = 0.
         endif
         if lct[j] eq 9 or lct[j] eq 10 or lct[j] eq 12 or lct[j] eq 13 or lct[j] eq 16 then begin  ; Assign grassland to the pixel
            tree[j] = 20.
            herb[j] = 80.
            bare[j] = 0.
         endif
       endif

; 2) Remove fires with no LCT assignment or in water bodies or snow/ice assigned by LCT
; 02/22/2019 - REMOVED ASSIGNMENT BASED ON GLC
    if lct[j] ge 17 or lct[j] le 0 or lct[j] eq 15 then begin ; Added Snow/Ice on 10/20/2009
       lct0 = lct0 + 1
       goto, skipfire
    endif
next1:

;yk: make sure that genveg got assigned somewhere for whatever mechanism.  
genveg = -9999

;###################################################################################################
;###################################################################################################
; SCENARIO #1 = LCT ONLY
;###################################################################################################
;###################################################################################################

; ######################################################
; Assign Generic land cover to fire based on
;   global location and lct information
; ######################################################
;Generic land cover codes (genveg) are as follows:
;1 grassland
;2 shrub
;3 Tropical Forest
;4 Temperate Forest
;5 Boreal Forest
;6 Temperate Evergreen Forest
;7 Pasture
;8 Rice
;9 Crop (generic)
;10  Wheat
;11  Cotton
;12  Soy
;13  Corn
;14  Sorghum
;15  Sugar Cane

    scenario1:
    ; yk: record which algorithm used
    scenuse[j] = 1

; 1) Grasslands and Savanna
     if lct[j] eq 9 or lct[j] eq 10 or lct[j] eq 11 or lct[j] eq 14 or lct[j] eq 16 then begin
        genveg = 1
        goto, endveg
    endif
; 2) Woody Savanna/ Shrubs
    if lct[j] ge 6 and lct[j] le 8 then begin
        genveg = 2
        goto, endveg
    endif
; 3) Croplands
    if lct[j] eq 12 then begin
        genveg = 9
        goto, endveg
    endif
; 4) Urban
    if lct[j] eq 13 then begin ; then assign genveg based on VCF cover in the pixel and reset the lct value (for emission factors)
        urbnum = urbnum+1
        if tree[j] lt 40 then begin
            genveg = 1        ; grasslands
            lct[j] = 10       ; set to grassland
         goto, endveg
       endif
        if tree[j] ge 40 and tree[j] lt 60 then begin
            genveg = 2  ; woody savannas
            lct[j] = 8 ; set to woody savanna
            goto, endveg
        endif
        if tree[j] ge 60 then begin                  ; assign forest based on latitude
            if lat[j] gt 50 then begin               ; 10/19/2009: Changed the latitude border to 50degrees N (from 60 before) and none in S. Hemisphere
            genveg = 5
            lct[j] = 1  ; set to evergreen needleleaf forest 
            goto, endveg
        endif else begin
            if lat[j] ge -30 and lat[j] le 30 then genveg = 3 else genveg = 4
            lct[j] = 5 ; set to mixed forest
            goto, endveg
        endelse
        endif
    endif
; 5) Forests (based on latitude)
    if lct[j] eq 2 then begin
	    if lat[j] ge -23.5 and lat[j] le 23.5 then begin 
		    genveg = 3 ; Tropical Forest
	    endif else begin
		    genveg = 4 ; Tropical Forest
	    endelse
    endif
	    	
    if lct[j] eq 4 then genveg = 4 ; Temperate Forest
    if lct[j] eq 1 then begin  ; Evergreen Needleleaf forests (06/20/2014 Changed this)
       if lat[j] gt 50. then genveg = 5 else genveg = 6   ; 6/20/2014: Changed this 
       goto, endveg                                      ; Assign Boreal for Lat > 50; Evergreen needlelead for all else
    endif
    if lct[j] eq 3 then begin  ; deciduous Needleleaf forests -- June 20, 2014: Left LCT = 3 same as old code. ONLY Changed Evergreen needleleaf forests
       if lat[j] gt 50. then genveg = 5 else genveg = 4   ; 10/19/2009: Changed the latitude border to 50degrees N (from 60 before) and none in S. Hemisphere
       goto, endveg                                      ; Assign Boreal for Lat > 50; Temperate for all else
    endif
    if lct[j] eq 5 then begin ; Mixed Forest, Assign Fuel Load by Latitude
       if lat[j] gt 50. then begin  ; 10/19/2009: Changed the latitude border to 50degrees N (from 60 before) and none in S. Hemisphere
         genveg = 5
         goto, endveg
       endif
       ; yk: tropics -23.5 to +23.5
       if lat[j] ge -23.5 and lat[j] le 23.5 then genveg = 3 else genveg = 4
    endif
endveg:

; ####################################################
; Assign Fuel Loads based on Generic land cover
;   and global region location
;   units are in g dry mass/m2
; ####################################################

    reg = globreg[j]-1   ; locate global region, get index
    if reg le -1 or reg gt 100 then begin
       ;print, 'Fire number:',j,' removed. Something is WRONG with global regions and fuel loads. Globreg =', globreg[j]
       noglobreg = noglobreg+1
       goto, skipfire
    endif
    
; Bmass now gets calculated as a function of tree cover, too.
    if genveg eq 9 then begin
            bmass1= 902.      ; 02/08/2019 changed from 1200. based on Akagi, van Leewuen and McCarty
    ;For Brazil from Elliott Campbell, 06/14/2010 - specific to sugar case
      if (lon[j] le -47.323 and lon[j] ge -49.156) and (lat[j] le -20.356 and lat[j] ge -22.708) then begin
            bmass1= 1100. 
      endif
    endif
    if genveg eq 1 then bmass1 = grfuel[reg]
    if genveg eq 2 then bmass1 = wsfuel[reg]
    if genveg eq 3 then bmass1 = tffuel[reg]
    if genveg eq 4 or genveg eq 6 then bmass1 = tefuel[reg] ; Added in new genveg eq 6 here (06/20/2014)
    if genveg eq 5 then bmass1 = bffuel[reg]
  
    if genveg eq 0 then begin
       printf, 9, 'Fire number:',j,' removed. Something is WRONG with generic vegetation. genveg = 0'
       genveg0 = genveg0 + 1
       goto, skipfire
    endif
    
    ; DEC. 09, 2009: Added correction 
    ; Assign boreal forests in Southern Asia the biomass density of the temperate forest for the region
    if genveg eq 5 and globreg[j] eq 11 then bmass1 = tefuel[reg]
    
    if bmass1 eq -1 then begin
        printf, 9, 'Fire number:',j,' removed. bmass assigned -1! 
        printf, 9, '    genveg =', genveg, ' and globreg = ', globreg[j], ' and reg = ', reg
        print, 'Fire number:',j,' removed. bmass assigned -1!
        print, '    genveg =', genveg, ' and globreg = ', globreg[j], ' and reg = ', reg
        STOP
        bmass0 = bmass0+1
       goto, skipfire
    endif


; ####################################################
; Assign Burning Efficiencies based on Generic
;   land cover (Hoezelmann et al. [2004] Table 5
; ####################################################
; *****************************************************************************************
; ASSIGN CF VALUES (Combustion Factors)
    if (tree[j] gt 60) then begin      ;FOREST
    ; Values from Table 3 Ito and Penner [2004]
        CF1 = 0.30          ; Live Woody
        CF3 = 0.90          ; Leafy Biomass
        CF4 = 0.90          ; Herbaceous Biomass
        CF5 = 0.90          ; Litter Biomass
        CF6 = 0.30          ; Dead woody
    endif
    if (tree[j] gt 40) and (tree[j] le 60) then begin   ;WOODLAND
      ; yk: fixed based on Ito 2004
      ; CF3 = exp(-0.013*(tree[j]/100.))     ; Apply to all herbaceous fuels
       CF3 = exp(-0.013*tree[j])     ; Apply to all herbaceous fuels
       CF1 = 0.30                   ; Apply to all coarse fuels in woodlands
                                    ; From Ito and Penner [2004]
    endif
    If (tree[j] le 40) then begin       ;GRASSLAND
       CF3 = 0.98 ;Range is between 0.44 and 0.98 - Assumed UPPER LIMIT!
    endif
; *******************************************************************************************
; Calculate the Mass burned of each classification (herbaceous, woody, and forest)
; These are in units of g dry matter/m2
; Bmass is the total burned biomass
; Mherb is the Herbaceous biomass burned
; Mtree is the Woody biomass burned

    pctherb = herb[j]/100.
    pcttree = tree[j]/100.
    coarsebm = bmass1
    herbbm = grfuel[reg]

; ###################################################################
; 02/08/2019
; Include updated fuel loading for North America (Global Region 1)
; based on earlier Texas project (FCCS Fuel Loadings)
; ##################################################################

; Determine if in North America
if globreg[j] eq 1 then begin
; Assign coarse and herb biomass based on lct 
      coarsebm = lcttree[lct[j]]
      herbbm = lctherb[lct[j]]
endif

;######################################################################
; DETERMINE BIOMASS BURNED
;  Grasslands
if tree[j] le 40 then begin
    Bmass = (pctherb*herbbm*CF3)+(pcttree*herbbm*CF3)
    ; Assumed here that litter biomass = herbaceous biomass and that the percent tree
    ;   in a grassland cell contributes to fire fuels... CHECK THIS!!!
    ; Assuming here that the duff and litter around trees burn
endif
; Woodlands
if (tree[j] gt 40) and (tree[j] le 60) then begin
       Bmass = (pctherb*herbbm*CF3) + (pcttree*(herbbm*CF3+coarsebm*CF1))
endif
; Forests
if tree[j] gt 60 then begin
       Bmass = (pctherb*herbbm*CF3) + (pcttree*(herbbm*CF3+coarsebm*CF1))
endif


; ####################################################
; Assign Emission Factors based on LCT code
; ####################################################

; CHRISTINE EDITING YO'S CODE THAT ISN'T COMPILING
; ; Edited again 02/04/2019
;if where(genveg eq [1:15]) eq -1 then begin
  if genveg eq -1 or genveg eq 0 then begin
    print,'Fire_emis> ERROR genveg not set correctly: '
    print,' scen (orig/used): ', scen, scenuse[j]
    print,' lc_orig(M/G/F/FC/T/TC): ', [lctorig[j]]
    print,' lc_new (M/G/F/FC/T/TC): ', [lct[j]]
    print,' tree: ', tree[j]
    print,' genveg: ', genveg
    print,'Fire_emis> ERROR stopping...'
    stop
  endif
;endif

; Reassigned emission factors based on LCT, not genveg for new emission factor table
    if lct[j] eq 1 then index = 0
    if lct[j] eq 2 then index = 1 
    if lct[j] eq 3 then index = 2
    if lct[j] eq 4 then index = 3
    if lct[j] eq 5 then index = 4
    if lct[j] eq 6 then index = 5
    if lct[j] eq 7 then index = 6
    if lct[j] eq 8 then index = 7
    if lct[j] eq 9 then index = 8
    if lct[j] eq 10 then index = 9
    if lct[j] eq 11 then index = 10
    if lct[j] eq 12 then index = 11
    if lct[j] eq 14 then index = 12
    if lct[j] eq 16 then index = 13
    if genveg eq 6 then index = 14 ; Added this on 06/20/2014 to account for temperate evergreen forests
    
; ####################################################
; Calculate Emissions
; ####################################################
; Emissions = area*BE*BMASS*EF
    ; Convert units to consistent units
     areanow = area[j]*1.0e6 ; convert km2 --> m2
     if acknowledge_flct then begin 
	     ; apply fractional land cover only if all LCTs for a given polygon are exported in preprocessor
         areanow = areanow*flct[j] 
     endif
     bmass = bmass/1000. ; convert g dm/m2 to kg dm/m2


; CW: MAY 29, 2015: Scale grassland and cropland fire areas 
; 02/04/2019 - removing ths scaling for crop/grassland fires. See FINNv1.5 - Amber suggested this. 
;   Removing this scaling for now.
;   if genveg eq 1 or genveg ge 8 then areanow = 0.75*areanow

; cw: 04/22/2015 - remove bare fraction from total area
;     REMOVE on 06/10/2015
;     Uncommented this 02/04/2019
     areanow = areanow - (areanow*(bare[j]/100.0)) ; remove bare area from being burned (04/21/2015)
     

; CALCULATE EMISSIONS kg
       CO = COEF[index]*areanow*bmass/1000.
       NMOC = NMOCEF[index]*areanow*bmass/1000.
       NOX = NOXEF[index]*areanow*bmass/1000.
       NO = NOEF[index]*areanow*bmass/1000.
       NO2 = NO2EF[index]*areanow*bmass/1000.
       SO2 = SO2EF[index]*areanow*bmass/1000.
       PM25 = PM25EF[index]*areanow*bmass/1000.
       OC = OCEF[index]*areanow*bmass/1000.
       BC = BCEF[index]*areanow*bmass/1000.
       NH3 = NH3EF[index]*areanow*bmass/1000.
       PM10 = PM10EF[index]*areanow*bmass/1000.



; Calculate totals for log file
bmassburn = bmass*areanow ; kg burned
BMASStotal = bmassburn+BMASStotal ; kg

if genveg eq 3 then begin
    TOTTROP = TOTTROP+bmassburn
    TOTTROParea = TOTTROPAREA+areanow
endif
if genveg eq 4 then begin
    TOTTEMP = TOTTEMP+bmassburn
    TOTTEMParea = TOTTEMParea+areanow
endif
if genveg eq 5 then begin
  TOTBOR = TOTBOR+bmassburn
  TOTBORarea = TOTBORarea+areanow
endif
if genveg eq 2 then begin
  TOTSHRUB = TOTSHRUB+bmassburn
  TOTSHRUBarea = TOTSHRUBarea+areanow
endif
if genveg ge 9 then begin
  TOTCROP = TOTCROP+bmassburn
  TOTCROParea = TOTCROParea+areanow
  TOTCROPCO = TOTCROPCO + CO
  TOTCROPPM25 = TOTCROPPM25 + PM25
endif
if genveg eq 1 then begin
  TOTGRAS = TOTGRAS+bmassburn
  TOTGRASarea = TOTGRASarea+areanow
endif

 ; units being output are in kg/day/fire
; ####################################################
; Print to Output file
; ####################################################
; NEW PRINT STATEMENT, 02/04/2019
;       printf, 6, 'longi,lat,polyid,fireid,jd,lct,genLC,pcttree,pctherb,pctbare,area,bmass,CO,NOx,NO,NO2,NH3,SO2,NMOC,PM25,PM10,OC,BC' 
;       form = '(D20.10,",",D20.10,",",(5(I10,",")),16(D25.10,","))'
printf, 6, format = form, lon[j],lat[j],polyid[j],fireid[j],jd[j],lct[j],genveg,tree[j],herb[j],bare[j],areanow,bmass,CO,NOx,NO,NO2,NH3,SO2,NMOC,PM25,PM10,OC,BC

; Calculate Global Sums
     COtotal = CO+COtotal
     NMOCtotal = NMOC+NMOCtotal
     NOXtotal = NOXtotal+NOx
     SO2total = SO2total+SO2
     PM25total = PM25total+PM25
     OCtotal = OCtotal+OC
     BCtotal = BCtotal+BC
     NH3total = NH3total+NH3
     PM10total = PM10total+PM10
     AREAtotal = AREAtotal+areanow ; m2         
       
; ####################################################
; End loop over Fires
; ####################################################

skipfire:
endfor ; End loop over fires

    t1 = systime(1)-t0
; PRINT SUMMARY TO LOG FILE
printf, 9, ' '
printf, 9, 'The time to do this run was: '+ $
       strtrim(string(fix(t1)/60,t1 mod 60, $
       format='(i3,1h:,i2.2)'),2)+'.'
printf, 9, ' This run was done on: ', SYSTIME()
printf, 9, ' '
printf, 9, 'The Input file was: ', infile
printf, 9, 'The Output file was: ', outfile
printf, 9, ' '
printf, 9, ' '

printf, 9, 'The emissions file was: ', emisin
printf, 9, ' The Fuel loading file was',Fuelin
printf, 9, 'The total number of fires input was:', numorig
printf, 9, '';printf, 9, 'the total number of fires in the tropics was: ', numadd
printf, 9, 'The number of fires processed (ngoodfires):', ngoodfires
printf, 9, ''
printf, 9, 'The number of urban fires: ', urbnum
printf, 9, ' The number of fires scaled to 100:', vcfcount
printf, 9, ' The number of fires with vcf < 50:', vcflt50
printf, 9, ' '
printf, 9, ' The number of fires skipped as not for the specific year:', yearnogood
printf, 9, ' The number of fires skipped due to 100% bare cover:', allbare
printf, 9, ' The number of fires skipped due to lct<= 0 or lct >= 17:', lct0
printf, 9, ' The number of fires removed because of no global region(not LCT 17):', noglobreg
printf, 9, ' The number of fires skipped due to Global Region = Antarctica:', antarc
printf, 9, ' The number of fires skipped due to problems with genveg:', genveg0
printf, 9, ' The number of fires skipped due to bmass assignments:', bmass0
printf, 9, ' '
printf, 9, 'Total number of fires skipped:', lct0+antarc+allbare+genveg0+bmass0+confnum+noglobreg+yearnogood
printf, 9, ''
; Added this section 08/24/2010
printf, 9, 'Global Totals (Tg) of biomass burned per vegetation type'
printf, 9, 'GLOBAL TOTAL (Tg) biomass burned (Tg),', BMASStotal/1.e9
printf, 9, 'Total Temperate Forests (Tg),', TOTTEMP/1.e9
printf, 9, 'Total Tropical Forests (Tg),', TOTTROP/1.e9
printf, 9, 'Total Boreal Forests (Tg),', TOTBOR/1.e9
printf, 9, 'Total Shrublands/Woody Savannah(Tg),', TOTSHRUB/1.e9
printf, 9, 'Total Grasslands/Savannas (Tg),', TOTGRAS/1.e9
printf, 9, 'Total Croplands (Tg),', TOTCROP/1.e9
printf, 9, ''
printf, 9, 'Global Totals (km2) of area per vegetation type'
printf, 9, 'TOTAL AREA BURNED (km2),', AREATOTAL/1000000.
printf, 9, 'Total Temperate Forests (km2),', TOTTEMParea/1000000.
printf, 9, 'Total Tropical Forests (km2),', TOTTROParea/1000000.
printf, 9, 'Total Boreal Forests (km2),', TOTBORarea/1000000.
printf, 9, 'Total Shrublands/Woody Savannah(km2),', TOTSHRUBarea/1000000.
printf, 9, 'Total Grasslands/Savannas (km2),', TOTGRASarea/1000000.
printf, 9, 'Total Croplands (km2),', TOTCROParea/1000000.
printf, 9, ''
printf, 9, 'TOTAL CROPLANDS CO (kg),', TOTCROPCO
printf, 9, 'TOTAL CROPLANDS PM2.5 (kg),', TOTCROPPM25
printf, 9, ''
printf, 9, 'GLOBAL TOTALS (Tg)'
printf, 9, 'CO = ', COtotal/1.e9
printf, 9, 'NMOC = ', NMOCtotal/1.e9
printf, 9, 'NOx = ', NOXtotal/1.e9
printf, 9, 'SO2 = ', SO2total/1.e9
printf, 9, 'PM2.5 = ', PM25total/1.e9
printf, 9, 'OC = ', OCtotal/1.e9
printf, 9, 'BC = ', BCtotal/1.e9
printf, 9, 'NH3 = ', NH3total/1.e9
printf, 9, 'PM10 = ', PM10total/1.e9
printf, 9, ''

; ***************************************************************
;           END PROGRAM
; ***************************************************************
    t1 = systime(1)-t0
    print,'Fire_emis> ' + simid + ' done.'
    print,'Fire_emis> infile was ' + infile
    print,'Fire_emis> End Procedure in   '+ $
       strtrim(string(fix(t1)/60,t1 mod 60, $
       format='(i3,1h:,i2.2)'),2)+'.'
    junk = check_math() ;This clears the math errors
    print, ' This run was done on: ', SYSTIME()
    close,/all   ;make sure ALL files are closed
end

pro global_fire_v2_02222019_yk3
;pro x_global_fire_v2_02222019_yk , infile=infile, simid=simid, yearnum=yearnum, todaydate=todaydate
;infile = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc\work_modvrs_na_2012\out_modvrs_na_2012_modlct_2012_modvcf_2012_regnum.csv' ; 2012 MODIS/VIIRS regional file 3/16/2019

preprocdir = 'D:\Data2\wildfire\TEXAS\New_2018\docker_201903\finn_preproc'

  simids = [ $
 ; 'mod_na_2012_keeppersistent' $ 
 ; ,'modvrs_na_2012_keeppersistent'$
   'mod_na_2012_droppersistent' $
  ,'modvrs_na_2012_droppersistent' $
  ,'modvrs_na_2013_droppersistent' $
  ,'modvrs_na_2014_droppersistent' $
  ,'modvrs_na_2015_droppersistent' $
  ,'modvrs_na_2016_droppersistent' $
  ,'modvrs_na_2017_droppersistent' $
  ]
  todaydate = '05212019'

;  simids = [ $
;;  'modvrs_global_2016_droppersistent' $
;  'modvrs_global_2018_droppersistent' $
;  ]
;  todaydate = '05032019'

  
  foreach simid, simids do begin
  
    x = simid.Split('_')
    yearstr = x[2]
    yearnum = fix(yearstr)
    
    rstyearnum = min([yearnum, 2017]) ; latest available now is 2017
    rstyearstr = strtrim(string(rstyearnum), 2)
    
    infile = preprocdir + '\work_' + simid + '\out_' + simid + '_modlct_' + rstyearstr + '_modvcf_' + rstyearstr + '_regnum.csv'

    input_lct = 'majority' ; traditional behavior
    ;input_lct = 'all'  ; choose this option when all LCT are exported in preprocessor

    print, infile
    print, simid
    print, yearnum
    print, input_lct
    
    
    x_global_fire_v2_02222019_yk3, infile, simid, yearnum, input_lct, todaydate
  
  endforeach
end
