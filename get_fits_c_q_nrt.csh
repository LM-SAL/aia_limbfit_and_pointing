#!/bin/csh
setenv TZ UTC
source /home/jsoc/.setJSOCenv
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
cd /home/jps/git/LimbFit
./get_fits_c_ymdh_nrt.pl -y=$1 -mo=$2 -da=$3 -h=$4 -dur=$5
/home/jps/git/aia_pointing/lf2mpr_nrt.pdl -in /surge40/jps/LimbFit_c/fits_nrt -out /surge40/jps/LimbFit_c/mpt3h -stg /surge40/jps/LimbFit_c/stage -sta -y=$1 -mo=$2 -da=$3 -h=$4
/home/jps/git/aia_pointing/update3h_mpt.pl -src /surge40/jps/LimbFit_c/stage -ser=aia.master_pointing3h -del
