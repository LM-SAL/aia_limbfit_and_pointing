#!/bin/csh
setenv TZ UTC
source /home/jsoc/.setJSOCenv
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
setenv ANA_DIR /home/jps/ana
setenv ANA_SLIB $ANA_DIR/slib/
setenv ANA_WLIB $ANA_DIR/wlib/
setenv FILES_FILE $1
setenv OUT_FILE $2
cd /home/jps/git/LimbFit
/home/jps/bin/ana limbcompute_driver.ana < /dev/null > /tmp/aialimbfit.out
rm $FILES_FILE
