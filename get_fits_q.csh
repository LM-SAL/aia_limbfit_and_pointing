#!/bin/csh
setenv TZ UTC
source /home/jsoc/.setJSOCenv
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
setenv ANA_DIR /home/jps/ana
setenv ANA_SLIB $ANA_DIR/slib/
setenv ANA_WLIB $ANA_DIR/wlib/
cd /home/jps/git/LimbFit
./get_paths.pl -y=$1 -mo=$2 -da=$3 -h=$4 -dur=$5
./get_fits_ymdh.pl -y=$1 -mo=$2 -da=$3 -h=$4 -dur=$5
