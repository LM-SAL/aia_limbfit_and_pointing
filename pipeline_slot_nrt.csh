#!/bin/csh -fe
if ($#argv != 4) then
  echo "Usage: $0 year month day hour"
  exit 2
endif

setenv TZ UTC
if (-f /home/jsoc/.setJSOCenv) then
  source /home/jsoc/.setJSOCenv
endif
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
set script_dir = $0:h
if ("$script_dir" == "") then
  set script_dir = .
endif
source $script_dir/config.csh
umask 0002
mkdir -p $MPT_DIR $STAGE_DIR
cd $REPO_ROOT
$PERL_BIN $REPO_ROOT/run_limbfit_ymdh.pl -y=$1 -mo=$2 -da=$3 -h=$4
$PERL_BIN $REPO_ROOT/lf2mpr_nrt.pdl -in $FITS_ROOT -out $MPT_DIR -stg $STAGE_DIR -sta -email -y=$1 -mo=$2 -da=$3 -h=$4
$PERL_BIN $REPO_ROOT/update3h_mpt.pl -src $STAGE_DIR -del
