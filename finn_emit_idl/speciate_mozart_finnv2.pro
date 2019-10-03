; $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

; 
; MARCH 12, 2109
; - Added new spciation conversion file
; - Edit to input new FINNv2 output format
; 
; 
; APril 01, 2019
; - Ran through a test file for Max
; - renamed and cleanded up for MAx
; 
;  $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

pro x_speciate_mozart_finnv2_02082019b_4MAX_yk3, infile, simid, yearnum, tdydate


close, /all

;*************************************************************************************************
;year = 2017
;yearnam = '2017'
year = yearnum
yearnam = string(yearnum)
;tdydate = 'mod_na_03172019'
;tdydate = 'TEST_Speciation_04012019'
tdydate = tdydate
; subsets arbitrary period within an year, specified by julian day
; defaulat not to filter at all, accept everything
firstday = -!values.f_infinity
lastday = !values.f_infinity

; infile = 'D:\Data2\wildfire\TEXAS\New_2018\EMISSIONS_CODE\OUTPUT_FILES\MARCH2019\modvrs_na_2012_03172019.txt' ; modis+ viirs 2012 (3/17/2019)
inpdir = './Inputs'
outdir = './Outputs/speciate'

if ~ file_test(outdir , /DIRECTORY) then begin
	file_mkdir, outdir
endif




;****************************************************************************************************
; CONVERSION FACTOR TABLE FOR VOCs
 
     convert =inpdir + '/New_Speciation_FEB2019.csv' 
 ;     intemp2=ascii_template(convert)
 ;     speciate=read_ascii(convert, template=intemp2)
      speciate=read_csv(convert);, template=intemp2)

; This file reads in the factors to apply to the VOC number to speciate to the MOZART4 species
; Takes fire emissions (kg/km2/day) and converts to mole species/km2/day
;

       sav = speciate.field2
       boreal = speciate.field3
   tropfor = speciate.field4
   tempfor = speciate.field5
     shrub = speciate.field6
        ag = speciate.field7

 

outfile = outdir + '/FINNv2_TXDomain_'+simid+'_'+tdydate+'_MOZ.txt' ; Ran on 11/03/2016
checkfile = outdir + '/LOG_FINNv2_TXDomain_'+simid+'_'+tdydate+'_MOZ.txt'


; Edited the output file on 02/23/2009
; edited 11/18/2009; added NO and NO2
openw, 5, outfile

; NEW WAY (March 10, 2011)
;                                    1    2     3    4     5  6   7  8   9   10  11   12 13 14   15   16   17      18     19     20   21    22   23   24   25   26   27   28       29     30    31       32      33    34     35     36  37    38   39   40   41    42   43  44   45  46   47     48      49     50
printf, 5, 'DAY,POLYID,FIREID,GENVEG,LATI,LONGI,AREA,BMASS,CO,NOx,NO,NO2,SO2,NH3,PM25,OC,BC,PM10,NMOC,APIN,BENZENE,BIGALK,BIGENE,BPIN,BZALD,C2H2,C2H4,C2H6,C3H6,C3H8,CH2O,CH3CH2OH,CH3CHO,CH3CN,CH3COCH3,CH3COOH,CH3OH,CRESOL,GLYALD,HCN,HCOOH,HONO,HYAC,ISOP,LIMON,MACR,MEK,MGLY,MVK,MYRC,PHENOL,TOLUENE,XYLENE,XYLOL' 
form='(I6,",",I12,",",I12,",",I6,50(",",F20.5))'


openw, 2, checkfile

; Open input file and get the needed variables
; INPUT FILES FROM MARCH 2019
;  1     2   3       4    5   6   7     8       9      10      11   12    13 14  15 16  17  18  19   20   21   22 23
; longi,lat,polyid,fireid,jd,lct,genLC,pcttree,pctherb,pctbare,area,bmass,CO,NOx,NO,NO2,NH3,SO2,NMOC,PM25,PM10,OC,BC
;	    intemp=ascii_template(infile)
;      fire=read_ascii(infile, template=intemp)
      fire=read_csv(infile)
        ; Emissions are in kg/km2/day

; Edited these fields on NOV. 18, 2009
    longi = fire.field01
    lati= fire.field02
    polyid = fire.field03
    fireid = fire.field04
    day = fire.field05
    jday = day
    lct = fire.field06
    genveg = fire.field07
		CO = fire.field13
		NOX = fire.field14
		NO = fire.field15
		NO2 = fire.field16
		NH3 = fire.field17
		SO2 = fire.field18
		VOC = fire.field19
		PM25 = fire.field20
		PM10 = fire.field21 ; Added 08/19/2010
		OC = fire.field22
		BC = fire.field23

		area = fire.field11 ; added 03/10/2011; should be in m2
    bmass = fire.field12
    
   	numfires = n_elements(day)
		nfires = numfires

print, 'Input file = ', infile
print, 'First day = ', min(day)
print, 'Last day = ', max(day)

; Set up output Arrays
    COemis = fltarr(numfires)
    NOXemis = fltarr(numfires)
    VOCemis = fltarr(numfires)
    SO2emis = fltarr(numfires)
    NH3emis = fltarr(numfires)
    PM25emis = fltarr(numfires)
    OCemis = fltarr(numfires)
  	BCEMIS = fltarr(numfires)
  	NOemis = fltarr(numfires)
  	NO2emis = fltarr(numfires)
  	PM10emis = fltarr(numfires)
; Set up speciated VOC arrays
  	APINemis = fltarr(numfires)
  	BENZENEemis = fltarr(numfires)
  	BIGALKemis = fltarr(numfires)
  	BIGENEemis = fltarr(numfires)
  	BPINemis = fltarr(numfires)
  	BZALDemis = fltarr(numfires)
  	C2H2emis = fltarr(numfires)
  	C2H4emis = fltarr(numfires)
  	C2H6emis = fltarr(numfires)
  	C3H6emis = fltarr(numfires)
  	C3H8emis = fltarr(numfires)
  	CH2Oemis = fltarr(numfires)
  	CH3CH2OHemis = fltarr(numfires)
  	CH3CHOemis = fltarr(numfires)
  	CH3CNemis = fltarr(numfires)
  	CH3COCH3emis = fltarr(numfires)
  	CH3COOHemis = fltarr(numfires)
  	CH3OHemis = fltarr(numfires)
  	CRESOLemis = fltarr(numfires)
  	GLYALDemis = fltarr(numfires)
  	HCNemis = fltarr(numfires)
  	HCOOHemis = fltarr(numfires)
  	HONOemis = fltarr(numfires)
  	HYACemis = fltarr(numfires)
  	ISOPemis = fltarr(numfires)
  	LIMONemis = fltarr(numfires)
  	MACRemis = fltarr(numfires)
  	MEKemis = fltarr(numfires)
  	MGLYemis = fltarr(numfires)
  	MVKemis = fltarr(numfires)
  	MYRCemis = fltarr(numfires)
  	PHENOLemis = fltarr(numfires)
  	TOLUENEemis = fltarr(numfires)
  	XYLENEemis = fltarr(numfires)
  	XYLOLemis = fltarr(numfires)

  	;01  APIN
  	;02  BENZENE
  	;03  BIGALK
  	;04  BIGENE
  	;05  BPIN
  	;06  BZALD
  	;07  C2H2
  	;08  C2H4
  	;09  C2H6
  	;10  C3H6
  	;11  C3H8
  	;12  CH2O
  	;13  CH3CH2OH
  	;14  CH3CHO
  	;15  CH3CN
  	;16  CH3COCH3
  	;17  CH3COOH
  	;18  CH3OH
  	;19  CRESOL
  	;20  GLYALD
  	;21  HCN
  	;22  HCOOH
  	;23  HONO
  	;24  HYAC
  	;25  ISOP
  	;26  LIMON
  	;27  MACR
  	;28  MEK
  	;29  MGLY
  	;30  MVK
  	;31  MYRC
  	;32  PHENOL
  	;33  TOLUENE
  	;34  XYLENE
  	;35 XYLOL  	

skip1 = 0L
skip2 = 0L
skip3 = 0L
    
;-------------------------------
; DO LOOP OVER ALL FIRES
; Convert VOC species and output most in mole/km2/day
;-------------------------------
for i = 0L,numfires-1 do begin

; Skip fires on last day
if year mod 4 eq 0 then begin
  ; for leap years
  if day[i] gt 366 then begin
    print,'year = ',year,' and day: ',jday[i],' not included.
    skip1 = skip1 + 1
    goto, skipfire
  endif
endif else begin
  ; For non-leap years
  if day[i] gt 365 then begin
    print,'year = ',year,' and day: ',jday[i],' not included.
    skip1 = skip1 + 1
    goto, skipfire
  endif 
endelse

; Make sure only include days of the months in the file (for WRF-CHEM)
if day[i] gt lastday or day[i] lt firstday then begin
  skip2 = skip2 + 1
  goto, skipfire
endif

	; Convert orignial emissions converted to mole/km2/day
	 
    	COemis[i]=CO[i]*1000./28.01
     	NH3emis[i]=NH3[i]*1000/17.03
    	NOemis[i] = NO[i]*1000/30.01 ; added 11/18/2009
    	NO2emis[i] = NO2[i]*1000/46.01
    	SO2emis[i]=SO2[i]*1000/64.06
    	
; NOX, VOC, and PM  emissions kept in kg/day/km2 (Not converted)
      NOXemis[i]=NOX[i] 
      VOCemis[i]=VOC[i]
      OCemis[i]=OC[i]
      BCemis[i]= BC[i]
      PM25emis[i]=PM25[i]
      PM10emis[i]=PM10[i] ; Added 08/19/2010
      
; GENERIC LAND COVER CLASSES
;    1 = grasslands and savanna
;    2 = woody savanna/shrublands
;    3 = tropical forest
;    4 = temperate forest
;    5 = boreal forest
;    9 = croplands
;    0 = no vegetation (should have been removed by now- but just in case...)

; STOP if no recognizable GenLC is in there
if genveg[i] eq 7 or genveg[i] eq 8 or genveg[i] eq 11 or genveg[i] eq 12 then STOP

; Tropical Forests (genveg = 3):
if (genveg[i] eq 1) then convert2MOZ4 = sav
if (genveg[i] eq 2) then convert2MOZ4 = shrub
if (genveg[i] eq 3) then convert2MOZ4 = tropfor
if (genveg[i] eq 4) then convert2MOZ4 = tempfor
if (genveg[i] eq 5) then convert2MOZ4 = boreal
if (genveg[i] eq 9) then convert2MOZ4 = ag
if (genveg[i] eq 6) then convert2MOZ4 = tempfor 

; Speciate VOC emissoins. VOC is in kg and the output of this is mole MOZ4 species
;0 APIN
;1 BENZENE
;2 BIGALK
;3 BIGENE
;4 BPIN
;5 BZALD
;6 C2H2
;7 C2H4
;8 C2H6
;9 C3H6
;10  C3H8
;11  CH2O
;12  CH3CH2OH
;13  CH3CHO
;14  CH3CN
;15  CH3COCH3
;16  CH3COOH
;17  CH3OH
;18  CRESOL
;19  GLYALD
;20  HCN
;21  HCOOH
;22  HONO
;23  HYAC
;24  ISOP
;25  LIMON
;26  MACR
;27  MEK
;28  MGLY
;29  MVK
;30  MYRC
;31  PHENOL
;32  TOLUENE
;33  XYLENE
;34  XYLOL

APINemis[i] = VOC[i]*convert2MOZ4[0]
BENZENEemis[i] = VOC[i]*convert2MOZ4[1]
BIGALKemis[i] = VOC[i]*convert2MOZ4[2]
BIGENEemis[i] = VOC[i]*convert2MOZ4[3]
BPINemis[i] = VOC[i]*convert2MOZ4[4]
BZALDemis[i] = VOC[i]*convert2MOZ4[5]
C2H2emis[i] = VOC[i]*convert2MOZ4[6]
C2H4emis[i] = VOC[i]*convert2MOZ4[7]
C2H6emis[i] = VOC[i]*convert2MOZ4[8]
C3H6emis[i] = VOC[i]*convert2MOZ4[9]
C3H8emis[i] = VOC[i]*convert2MOZ4[10]
CH2Oemis[i] = VOC[i]*convert2MOZ4[11]
CH3CH2OHemis[i] = VOC[i]*convert2MOZ4[12]
CH3CHOemis[i] = VOC[i]*convert2MOZ4[13]
CH3CNemis[i] = VOC[i]*convert2MOZ4[14]
CH3COCH3emis[i] = VOC[i]*convert2MOZ4[15]
CH3COOHemis[i] = VOC[i]*convert2MOZ4[16]
CH3OHemis[i] = VOC[i]*convert2MOZ4[17]
CRESOLemis[i] = VOC[i]*convert2MOZ4[18]
GLYALDemis[i] = VOC[i]*convert2MOZ4[19]
HCNemis[i] = VOC[i]*convert2MOZ4[20]
HCOOHemis[i] = VOC[i]*convert2MOZ4[21]
HONOemis[i] = VOC[i]*convert2MOZ4[22]
HYACemis[i] = VOC[i]*convert2MOZ4[23]
ISOPemis[i] = VOC[i]*convert2MOZ4[24]
LIMONemis[i] = VOC[i]*convert2MOZ4[25]
MACRemis[i] = VOC[i]*convert2MOZ4[26]
MEKemis[i] = VOC[i]*convert2MOZ4[27]
MGLYemis[i] = VOC[i]*convert2MOZ4[28]
MVKemis[i] = VOC[i]*convert2MOZ4[29]
MYRCemis[i] = VOC[i]*convert2MOZ4[30]
PHENOLemis[i] = VOC[i]*convert2MOZ4[31]
TOLUENEemis[i] = VOC[i]*convert2MOZ4[32]
XYLENEemis[i] = VOC[i]*convert2MOZ4[33]
XYLOLemis[i] = VOC[i]*convert2MOZ4[34]


; CHECK HERE IF SOMETHING IS WEIRD
if C2H6emis[i] eq 0 then begin
	 print,'fire = ',i+1,' and day: ',jday[i],' not included.
	 skip3 = skip3 + 1
	 goto, skipfire
endif

; Print to output file
;                         1      2         3         4          1       2        3       4        5         6          7          8
;	                        DAY,   POLYID,   FIREID,   GENVEG,    LATI,   LONGI,   AREA,   BMASS,   CO,       NOx,       NO,        NO2,      
printf, 5, format = form, day[i],polyid[i],fireid[i],genveg[i], lati[i],longi[i],area[i],bmass[i],COemis[i],NOxemis[i],NOemis[i], NO2emis[i],$
; 9           10          11           12        13        14          15         16           17             18            19 
; SO2,        NH3,        PM25,        OC,       BC,       PM10,       NMOC,      APIN,        BENZENE,       BIGALK,       BIGENE,
  SO2emis[i], NH3emis[i], PM25emis[i], OCemis[i],BCemis[i],PM10emis[i],VOCemis[i],APINemis[i], BENZENEemis[i],BIGALKemis[i],BIGENEemis[i], $

; 20          21           22          23          24          25          26          27          28              29            30           31
;	BPIN,       BZALD,       C2H2,       C2H4,       C2H6,       C3H6,       C3H8,       CH2O,       CH3CH2OH,       CH3CHO,       CH3CN,       CH3COCH3,
	BPINemis[i],BZALDemis[i],C2H2emis[i],C2H4emis[i],C2H6emis[i],C3H6emis[i],C3H8emis[i],CH2Oemis[i],CH3CH2OHemis[i],CH3CHOemis[i],CH3CNemis[i],CH3COCH3emis[i], $

; 32             33           34            35            36         37           38          39          40          41           42          43         44      
; CH3COOH,       CH3OH,       CRESOL,       GLYALD,       HCN,       HCOOH,       HONO,       HYAC,       ISOP,       LIMON,       MACR,       MEK,       MGLY,
	CH3COOHemis[i],CH3OHemis[i],CRESOLemis[i],GLYALDemis[i],HCNemis[i],HCOOHemis[i],HONOemis[i],HYACemis[i],ISOPemis[i],LIMONemis[i],MACRemis[i],MEKemis[i],MGLYemis[i], $
;
; 45         46          
; MVK,       MYRC,       PHENOL,       TOLUENE,       XYLENE,       XYLOL   
  MVKemis[i],MYRCemis[i],PHENOLemis[i],TOLUENEemis[i],XYLENEemis[i],XYLOLemis[i]
  

skipfire:

endfor ; end of i loop


; PRINT INFORMATION TO LOG FILE
printf, 2, ' '
printf, 2, 'The input file was: ', infile
printf, 2, 'The speciation file was: ', convert
printf, 2, 'skip 1, 2, 3', skip1, skip2, skip3
printf, 2, ' '
printf, 2, ' Original from fire emissions model before speciation'
printf, 2, 'The total CO emissions (moles, Tg) =  ',  total(COemis), ",",total(CO)/1.e9
printf, 2, 'The total NO emissions (moles, Tg) =  ',  total(NOemis), ",",total(NO)/1.e9
printf, 2, 'The total NOx emissions (Tg) = ', total(NOX)/1.e9 
printf, 2, 'The total NO2 emissions (moles, Tg) = ',  total(NO2emis), ",",total(NO2)/1.e9
printf, 2, 'The total SO2 emissions (moles, Tg) = ',  total(SO2emis), ",",total(SO2)/1.e9
printf, 2, 'The total NH3 emissions (moles, Tg) = ',  total(NH3emis), ",",total(NH3)/1.e9
;printf, 2, 'The total H2 emissions (moles, Tg) = ',  total(H2emis), ",",total(H2)/1.e9
printf, 2, 'The total VOC emissions (Tg) =',  total(VOC)/1.e9
printf, 2, 'The total OC emissions (Tg) =',  total(OCemis)/1.e9
printf, 2, 'The total BC emissions (Tg) =',  total(BCemis)/1.e9
printf, 2, 'The total PM10 emissions (Tg) = ', total(PM10emis)/1.e9
printf, 2, 'The total PM2.5 emissions (Tg) = ', total(PM25emis)/1.e9
Printf, 2, ' '
Printf, 2, 'SUMMARY FROM MOZART4 speciation'
printf, 2, 'The total BIGENE emissio (moles) =',  total(BIGENEemis)
printf, 2, 'The total C2H6 emissions (moles) =',  total(C2H6emis), ', and in Tg = ', total(C2H6emis)*30.07/1.e12
printf, 2, 'The total MEK emissions (moles) =',  total(MEKemis)
printf, 2, 'The total TOLUENE emiss (moles) =',   total(TOLUENEemis), ', and in Tg = ', total(TOLUENEemis)*90.1/1.e12
printf, 2, 'The total CH2O emissions (moles) =',  total(CH2Oemis), ', and in Tg = ', total(CH2Oemis)*30.3/1.e12
printf, 2, 'The total HCOOH emissions (moles) =', total(HCOOHemis), ', and in Tg = ', total(HCOOHemis)*47.02/1.e12
printf, 2, 'The total C2H2 emissions (moles) = ', total(C2H2emis), ', and in Tg = ', total(C2H2emis)*26.04/1.e12
printf, 2, 'The total GLYALD emissions (moles) = ', total(GLYALDemis)
printf, 2, 'The total ISOPRENE emissions (moles) = ', total(ISOPemis), ', and in Tg = ', total(ISOPemis)*68.12/1.e12
printf, 2, 'The total HCN emissions (moles) = ', total(HCNemis), ', and in Tg = ', total(HCNemis)*27.025/1.e12
printf, 2, 'The total CH3CN emissions (moles) = ', total(CH3CNemis), ', and in Tg = ', total(CH3CNemis)*41.05/1.e12
printf, 2, 'The total CH3OH emissions (moles) = ', total(CH3OHemis), ', and in Tg = ', total(CH3OHemis)*32.04/1.e12
printf, 2, 'The total C2H4 emissions (moles) = ', total(C2H4emis), ', and in Tg = ', total(C2H4emis)*28.05/1.e12
printf, 2, ''

printf, 2, ''


; **************************** REGIONAL SUMS *******************************
Printf, 2, 'GLOBAL TOTALS (Tg Species)'
printf, 2, 'CO, ', total(CO)/1.e9
printf, 2, 'NOX, ', total(NOX)/1.e9
printf, 2, 'NO, ', total(NO)/1.e9
printf, 2, 'NO2, ', total(NO2)/1.e9
printf, 2, 'NH3, ', total(NH3)/1.e9
printf, 2, 'SO2, ', total(SO2)/1.e9
printf, 2, 'VOC, ', total(VOC)/1.e9
printf, 2, 'OC, ', total(OC)/1.e9
printf, 2, 'BC, ', total(BC)/1.e9
printf, 2, 'PM2.5, ', total(PM25)/1.e9
printf, 2, 'PM20, ', total(PM10)/1.e9

; WESTERN U.S. 
westUS = where(lati gt 24. and lati lt 49. and longi gt -125. and longi lt -100.)   
printf, 2, 'Western US (Gg Species)'
printf, 2, 'CO, ', total(CO[westUS])/1.e6
printf, 2, 'NOX, ', total(NOX[westUS])/1.e6
printf, 2, 'NO, ', total(NO[westUS])/1.e6
printf, 2, 'NO2, ', total(NO2[westUS])/1.e6
printf, 2, 'NH3, ', total(NH3[westUS])/1.e6
printf, 2, 'SO2, ', total(SO2[westUS])/1.e6
printf, 2, 'VOC, ', total(VOC[westUS])/1.e6
printf, 2, 'OC, ', total(OC[westUS])/1.e6
printf, 2, 'BC, ', total(BC[westUS])/1.e6
printf, 2, 'PM2.5, ', total(PM25[westUS])/1.e6
printf, 2, 'PM10, ',  total(PM10[westUS])/1.e6

; EASTERN U.S. 
eastUS = where(lati gt 24. and lati lt 49. and longi gt -100. and longi lt -60.)   
printf, 2, 'Eastern US (Gg Species)'
printf, 2, 'CO, ', total(CO[eastUS])/1.e6
printf, 2, 'NOX, ', total(NOX[eastUS])/1.e6
printf, 2, 'NO, ', total(NO[eastUS])/1.e6
printf, 2, 'NO2, ', total(NO2[eastUS])/1.e6
printf, 2, 'NH3, ', total(NH3[eastUS])/1.e6
printf, 2, 'SO2, ', total(SO2[eastUS])/1.e6
printf, 2, 'VOC, ', total(VOC[eastUS])/1.e6
printf, 2, 'OC, ', total(OC[eastUS])/1.e6
printf, 2, 'BC, ', total(BC[eastUS])/1.e6
printf, 2, 'PM2.5, ', total(PM25[eastUS])/1.e6
printf, 2, 'PM10, ',  total(PM10[eastUS])/1.e6

; CANADA/AK 
CANAK = where(lati gt 49. and lati lt 70. and longi gt -170. and longi lt -55.)   
printf, 2, 'Canada/Alaska (Gg Species)'
printf, 2, 'CO, ', total(CO[CANAK])/1.e6
printf, 2, 'NOX, ', total(NOX[CANAK])/1.e6
printf, 2, 'NO, ', total(NO[CANAK])/1.e6
printf, 2, 'NO2, ', total(NO2[CANAK])/1.e6
printf, 2, 'NH3, ', total(NH3[CANAK])/1.e6
printf, 2, 'SO2, ', total(SO2[CANAK])/1.e6
printf, 2, 'VOC, ', total(VOC[CANAK])/1.e6
printf, 2, 'OC, ', total(OC[CANAK])/1.e6
printf, 2, 'BC, ', total(BC[CANAK])/1.e6
printf, 2, 'PM2.5, ', total(PM25[CANAK])/1.e6
printf, 2, 'PM10, ',  total(PM10[CANAK])/1.e6


; Mexico and Central America 
MXCA = where(lati gt 10. and lati lt 28. and longi gt -120. and longi lt -65.)   
printf, 2, 'Mexico/Central America (Gg Species)'
printf, 2, 'CO, ', total(CO[MXCA])/1.e6
printf, 2, 'NOX, ', total(NOX[MXCA])/1.e6
printf, 2, 'NO, ', total(NO[MXCA])/1.e6
printf, 2, 'NO2, ', total(NO2[MXCA])/1.e6
printf, 2, 'NH3, ', total(NH3[MXCA])/1.e6
printf, 2, 'SO2, ', total(SO2[MXCA])/1.e6
printf, 2, 'VOC, ', total(VOC[MXCA])/1.e6
printf, 2, 'OC, ', total(OC[MXCA])/1.e6
printf, 2, 'BC, ', total(BC[MXCA])/1.e6
printf, 2, 'PM2.5, ', total(PM25[MXCA])/1.e6
printf, 2, 'PM10, ',  total(PM10[MXCA])/1.e6


; End Program
close, /all
;stop
print, 'Progran Ended! All done!'
END

pro speciate_mozart_finnv2
  datadir = './Outputs'
  simids = [ $
  'modvrs_na_2012' $
  ,'modvrs_na_2013' $
  ,'modvrs_na_2014' $
  ,'modvrs_na_2015' $
  ,'modvrs_na_2016' $
  ,'modvrs_na_2017' $
  ,'modvrs_na_2018' $
  ]
  finndate = '10032019'
  todaydate = '10032019'


;  simids = [ $
;  'modvrs_global_2016_droppersistent' $
; ,'modvrs_global_2018_droppersistent' $
;  ]
;  finndate = '05032019'
;  todaydate = '05032019'


  foreach simid, simids do begin

    x = simid.Split('_')
    yearstr = x[2]
    yearnum = fix(yearstr)
    infile = datadir +  '/' + simid + '_' + finndate + '.txt'
    print, infile
    print, simid
    print, yearnum


    x_speciate_mozart_finnv2_02082019b_4max_yk3, infile, simid, yearnum, todaydate

  endforeach
  
end
