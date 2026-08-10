#!/bin/csh -f
# scan_lev1_bad_pointing.csh — day-by-day scan of aia.lev1 for bad pointing.
#
# Finds records whose CRPIX1/CRPIX2/R_SUN are NaN, zero, or negative, or whose
# CRVAL1/CRVAL2 are NaN (zero is the nominal CRVAL). Appends one line per bad
# record ("T_OBS FSN WAVELNTH") to the output file. Progress is checkpointed
# after each day, so rerunning the script resumes where it left off.
#
# Usage: scan_lev1_bad_pointing.csh [start-date [end-date]]   (YYYY-MM-DD)
#        defaults: 2010-05-01 .. today

setenv TZ UTC
if (-f /home/jsoc/.setJSOCenv) then
  source /home/jsoc/.setJSOCenv
endif
setenv SUMSERVER k1
set script_dir = $0:h
if ("$script_dir" == "") then
  set script_dir = .
endif
source $script_dir/config.csh

set show_info = $DRMS_BINS_INSTALL_DIR/show_info
set out       = lev1_bad_pointing.txt
set progress  = lev1_bad_pointing.progress
set filter    = "[? CRPIX1='NaN' or CRPIX2='NaN' or R_SUN='NaN' or CRVAL1='NaN' or CRVAL2='NaN' or CRPIX1<=0 or CRPIX2<=0 or R_SUN<=0 ?]"

set start = 2010-05-01
set end   = `date +%F`
if ($#argv >= 1) set start = $1
if ($#argv >= 2) set end = $2
if (-f $progress) then
  set last  = `cat $progress`
  set start = `date -d "$last + 1 day" +%F`
  echo "Resuming from $start (last completed day: $last)"
endif

set tmp = /tmp/scan_lev1_bad_pointing.$$
set day = $start
while (`date -d $day +%s` <= `date -d $end +%s`)
  set ds_day = `date -d $day +%Y.%m.%d`
  $show_info -q ds="aia.lev1[${ds_day}/1d]$filter" key=T_OBS,FSN,WAVELNTH > $tmp
  if ($status != 0) then
    echo "show_info failed on $day; rerun to resume from there"
    rm -f $tmp
    exit 1
  endif
  grep '^[0-9]' $tmp >> $out
  echo $day > $progress
  set day = `date -d "$day + 1 day" +%F`
end
rm -f $tmp
echo "Done: $start .. $end, bad records in $out"
