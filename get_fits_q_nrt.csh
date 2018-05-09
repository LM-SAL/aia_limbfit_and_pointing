#!/bin/csh
setenv TZ UTC
source /home/jsoc/.setJSOCenv
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
setenv ANA_DIR /home/jps/ana
setenv ANA_SLIB $ANA_DIR/slib/
setenv ANA_WLIB $ANA_DIR/wlib/
cd /home/jps/git/LimbFit
/home/jps/bin/get_paths_nrt.pl -y=$1 -mo=$2 -da=$3 -h=$4 -dur=$5
./get_fits_ymdh_nrt.pl -y=$1 -mo=$2 -da=$3 -h=$4 -dur=$5
/home/jps/git/aia_pointing/lf2mpr_nrt.pdl -in /surge28/jsocprod/jps/LimbFit/fits_nrt -out /surge28/jsocprod/jps/LimbFit/mpt3h_nrt -stg /surge28/jsocprod/jps/LimbFit/stage_nrt -sta -y=$1 -mo=$2 -da=$3 -h=$4
#/home/jps/git/aia_pointing/update3h_mpt.pl -src /surge28/jsocprod/jps/LimbFit/stage_nrt -ser=aia.master_pointing3h
/home/jps/bin/update3h_mpt.pl -src /surge28/jsocprod/jps/LimbFit/stage_nrt -ser=lm_jps.master_pointing3h
/home/jps/git/aia_pointing/update3h_mpt.pl -src /surge28/jsocprod/jps/LimbFit/stage_nrt -ser=lm_jps.mp3h -del
