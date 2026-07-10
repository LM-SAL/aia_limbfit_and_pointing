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
source /home/nabil/Git/aia_limbfit_and_pointing/config.csh
umask 0002
mkdir -p $MPT_DIR $STAGE_DIR
cd $REPO_ROOT
$PERL_BIN $REPO_ROOT/run_limbfit_ymdh.pl -y=$1 -mo=$2 -da=$3 -h=$4
$PERL_BIN $REPO_ROOT/lf2mpr_nrt.pdl -in $FITS_ROOT -out $MPT_DIR -stg $STAGE_DIR -sta -email -require-all -y=$1 -mo=$2 -da=$3 -h=$4
$PERL_BIN $REPO_ROOT/update3h_mpt.pl -src $STAGE_DIR -del
