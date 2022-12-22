pro merge_fire_files

  sdum = ''

  path_fires_nopoly = '/data14a/FINN/processed_fires_finn2.5/'
  path_fires = '/data14a/FINN/finnv2.3/processed_fires/'

 for year = 2013,2020 do begin
  syr = String(year,format='(i4)')
  syrprev = String((year-1),format='(i4)')

  if (year mod 4 eq 0) then ndayyr = 366 else ndayyr = 365
  print, year, ndayyr

  file_withpoly = path_fires+'out_global_modvrs_'+syr+'_modlct_'+syrprev+'_modvcf_'+syrprev+'_regnum.csv'
  file_without = path_fires_nopoly+'out_global_modvrs_'+syr+'_no_lrg_poly_modlct_'+syrprev+'_modvcf_'+syrprev+'_regnum.csv'
  file_new = path_fires_nopoly+'fires_modvrs_merged_'+syr+'.csv'

  file_log = 'log_modvrs_merged_'+syr+'.out'
  openw,ilun_log,file_log,/get_lun

  nfire_wi = File_lines(file_withpoly)-1
  nfire_wo = File_lines(file_without)-1

  print,'reading ',file_withpoly
  printf,ilun_log,file_withpoly
  openr,ilun1,file_withpoly,/get_lun
  readf,ilun1,sdum
  print,sdum
  printf,ilun_log,sdum
;polyid,fireid,cen_lon,cen_lat,acq_date_lst,area_sqkm,v_lct,f_lct,v_tree,v_herb,v_bare,v_regnum
  file_header = sdum
  colnames1 = Strsplit(sdum,',',/extract)
  nvar1 = n_elements(colnames1)
  nfires = nfire_wi
  idpoly_wi = lonarr(nfires) 
  idfire_wi = lonarr(nfires)
  lon_wi = fltarr(nfires)
  lat_wi = fltarr(nfires)
  sdate_wi = strarr(nfires)
  doy_wi = intarr(nfires)
  area_wi = fltarr(nfires)
  lct_wi = intarr(nfires)
  flct_wi = fltarr(nfires)
  ftree_wi = fltarr(nfires)
  fherb_wi = fltarr(nfires)
  fbare_wi = fltarr(nfires)
  regnum_wi = intarr(nfires)

  for i=0L,nfires-1 do begin
     readf,ilun1,sdum
     parts = strsplit(sdum,',',/extract,/preserve_null)
     if (n_elements(parts) lt 12) then goto,skipfire
     if (strlen(parts[11]) lt 1) then goto,skipfire
     yy = Fix(Strmid(parts[4],0,4))
     mm = Fix(Strmid(parts[4],5,2))
     dd = Fix(Strmid(parts[4],8,2))
     doy_wi[i] = Julday(mm,dd,yy) - julday(1,1,year) +1
    
        idpoly_wi[i] = Long(parts[0])
        idfire_wi[i] = Long(parts[1])
        lon_wi[i] = Float(parts[2])
        lat_wi[i] = Float(parts[3])
        sdate_wi[i] = parts[4]
        area_wi[i] = Float(parts[5])
        lct_wi[i] = Fix(parts[6])
        flct_wi[i] = Float(parts[7])
        ftree_wi[i] = float(parts[8])
        fherb_wi[i] = float(parts[9])
        fbare_wi[i] = float(parts[10])
        regnum_wi[i] = fix(parts[11])
       skipfire:
  endfor
  free_lun,ilun1

  print,'reading ',file_without
  printf,ilun_log,'reading ',file_without
  openr,ilun1,file_without,/get_lun
  readf,ilun1,sdum
  print,sdum
  printf,ilun_log,sdum
;polyid,fireid,cen_lon,cen_lat,acq_date_lst,area_sqkm,v_lct,f_lct,v_tree,v_herb,v_bare,v_regnum,fireid0
  colnames1 = Strsplit(sdum,',',/extract)
  nvar1 = n_elements(colnames1)
  nfires = nfire_wo
        idpoly_wo = lonarr(nfires) 
        idfire_wo = lonarr(nfires)
        lon_wo = fltarr(nfires)
        lat_wo = fltarr(nfires)
        sdate_wo = strarr(nfires)
        doy_wo = intarr(nfires)
        area_wo = fltarr(nfires)
        lct_wo = intarr(nfires)
        flct_wo = fltarr(nfires)
        ftree_wo = fltarr(nfires)
        fherb_wo = fltarr(nfires)
        fbare_wo = fltarr(nfires)
        regnum_wo = intarr(nfires)
        fireid0  = lonarr(nfires)
  
  for i=0L,nfires-1 do begin
     readf,ilun1,sdum
     parts = strsplit(sdum,',',/extract,/preserve_null)
     if (n_elements(parts) lt 12) then goto,skipfire2
     if (strlen(parts[11]) lt 1) then goto,skipfire2
     yy = Fix(Strmid(parts[4],0,4))
     mm = Fix(Strmid(parts[4],5,2))
     dd = Fix(Strmid(parts[4],8,2))
     doy_wo[i] = Julday(mm,dd,yy) - julday(1,1,year) +1
    
        idpoly_wo[i] = Long(parts[0])
        idfire_wo[i] = Long(parts[1])
        lon_wo[i] = Float(parts[2])
        lat_wo[i] = Float(parts[3])
        sdate_wo[i] = parts[4]
        area_wo[i] = Float(parts[5])
        lct_wo[i] = Fix(parts[6])
        flct_wo[i] = Float(parts[7])
        ftree_wo[i] = float(parts[8])
        fherb_wo[i] = float(parts[9])
        fbare_wo[i] = float(parts[10])
        regnum_wo[i] = fix(parts[11])
        fireid0[i] = Long(parts[12])
       skipfire2:
  endfor
  free_lun,ilun1
  help, nfire_wi,nfire_wo

  printf,ilun_log,'writing: ',file_new

  openw,ilun_out,file_new,/get_lun
  printf,ilun_out,file_header
  
  ; Loop through each day
  for day = 1,ndayyr do begin

   print,'day ',day
   printf,ilun_log,'day ',day
   indday_i = where(doy_wi eq day,ni)
   indday_o = where(doy_wo eq day,no)
   printf,ilun_log,'nfires: ',ni,no
   if (ni eq 0 or no eq 0) then goto,skipday

   fid_day_i = idfire_wi[indday_i]
   fid_day_o = fireid0[indday_o]
   
   ; get subsets for all arrays for this day
   d_idpoly_wi = idpoly_wi[indday_i]
   d_lon_wi = lon_wi[indday_i]
   d_lat_wi = lat_wi[indday_i]
   d_sdate_wi = sdate_wi[indday_i]
   d_area_wi = area_wi[indday_i]
   d_lct_wi = lct_wi[indday_i]
   d_flct_wi = flct_wi[indday_i]
   d_ftree_wi = ftree_wi[indday_i]
   d_fherb_wi = fherb_wi[indday_i]
   d_fbare_wi = fbare_wi[indday_i]
   d_regnum_wi = regnum_wi[indday_i]

   d_idpoly_wo = idpoly_wo[indday_o]
   d_lon_wo = lon_wo[indday_o]
   d_lat_wo = lat_wo[indday_o]
   d_sdate_wo = sdate_wo[indday_o]
   d_area_wo = area_wo[indday_o]
   d_lct_wo = lct_wo[indday_o]
   d_flct_wo = flct_wo[indday_o]
   d_ftree_wo = ftree_wo[indday_o]
   d_fherb_wo = fherb_wo[indday_o]
   d_fbare_wo = fbare_wo[indday_o]
   d_regnum_wo = regnum_wo[indday_o]

   ;get unique fire IDs from original file (with large polygons)
   uniq_fireid = fid_day_i[Uniq(fid_day_i, Sort(fid_day_i))]
   nuniq = n_elements(uniq_fireid)
   printf,ilun_log,'N unique fire ids: ',nuniq

  for j=0,nuniq-1 do begin
     id1 = uniq_fireid[j]
     if (id1 le 0) then goto,skipfire3
     ind_wi = where(fid_day_i eq id1,npolyi)
     ind_wo = where(fid_day_o eq id1,npolyo)
     if ((npolyi gt 1) and (npolyo gt 0)) then begin
        area_tree_wi = 0.
        area_herb_wi = 0.
        area_tree_wo = 0.
        area_herb_wo = 0.
        for ii = 0,npolyi-1 do begin
           area_tree_wi = area_tree_wi + d_ftree_wi[ind_wi[ii]]*d_area_wi[ind_wi[ii]]
           area_herb_wi = area_herb_wi + d_fherb_wi[ind_wi[ii]]*d_area_wi[ind_wi[ii]]
        endfor
        for io = 0,npolyo-1 do begin
           area_tree_wo = area_tree_wo + d_ftree_wo[ind_wo[io]]*d_area_wo[ind_wo[io]]
           area_herb_wo = area_herb_wo + d_fherb_wo[ind_wo[io]]*d_area_wo[ind_wo[io]]
        endfor
        if (area_tree_wi eq 0 and area_herb_wi eq 0) then goto,skipfire3
        if (area_tree_wo eq 0 and area_herb_wo eq 0) then goto,skipfire3

        treefrac_wi = area_tree_wi / (area_tree_wi+area_herb_wi)
        treefrac_wo = area_tree_wo / (area_tree_wo+area_herb_wo)
        if (treefrac_wi gt 0.5) then begin
           for ii = 0,npolyi-1 do begin
              i = ind_wi[ii]
              printf,ilun_out,format='(i10,",",i10,",",2(f10.5,","),a12,",",f6.3,",",i3,4(",",f8.3),",",i3)', $
                     d_idpoly_wi[i],id1,d_lon_wi[i],d_lat_wi[i],d_sdate_wi[i],d_area_wi[i],d_lct_wi[i],d_flct_wi[i],d_ftree_wi[i],d_fherb_wi[i],d_fbare_wi[i],d_regnum_wi[i]
           endfor 

        endif else begin
           for io = 0,npolyo-1 do begin
              i = ind_wo[io]
              printf,ilun_out,format='(i10,",",i10,",",2(f10.5,","),a12,",",f6.3,",",i3,4(",",f8.3),",",i3)', $
              d_idpoly_wo[i],id1,d_lon_wo[i],d_lat_wo[i],d_sdate_wo[i],d_area_wo[i],d_lct_wo[i],d_flct_wo[i],d_ftree_wo[i],d_fherb_wo[i],d_fbare_wo[i],d_regnum_wo[i]
           endfor 
        endelse
                
     endif else begin
        printf,ilun_log,'no match for fire id: ',id1
        for ii = 0,npolyi-1 do begin
          i = ind_wi[ii]
          printf,ilun_out,format='(i10,",",i10,",",2(f10.5,","),a12,",",f6.3,",",i3,4(",",f8.3),",",i3)', $
             d_idpoly_wi[i],id1,d_lon_wi[i],d_lat_wi[i],d_sdate_wi[i],d_area_wi[i],d_lct_wi[i],d_flct_wi[i],d_ftree_wi[i],d_fherb_wi[i],d_fbare_wi[i],d_regnum_wi[i]
           endfor 

     endelse
     
     skipfire3:

  endfor 

  skipday:
 endfor 
 free_lun,ilun_out
 print,'wrote: ',file_new

 free_lun,ilun_log
endfor

end

