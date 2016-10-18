#!/bin/tcsh
setenv TZ UTC
source /home/jsoc/.setJSOCenv
setenv SUMSERVER k1
source /SGE2/default/common/settings.csh
setenv ANA_DIR /home/jps/ana
setenv ANA_SLIB $ANA_DIR/slib/
setenv ANA_WLIB $ANA_DIR/wlib/
cd $HOME/git/LimbFit
$HOME/bin/ana limbcompute_driver.ana < /dev/null > /tmp/aialimbfit.out
rm $FILES_FILE
