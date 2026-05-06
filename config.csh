#!/bin/csh
# config.csh — Deployment paths for the AIA limbfit / pointing NRT pipeline.
# Source this file near the top of pipeline wrapper scripts.

setenv SUMSERVER k1
setenv TZ        UTC

set PERL_BIN   = /home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
set REPO_ROOT  = /home/nabil/Git/aia_limbfit_and_pointing
set FITS_ROOT  = /surge40/nabil/LimbFit_c/fits_nrt
set MPT_DIR    = /surge40/nabil/LimbFit_c/mpt3h
set STAGE_DIR  = /surge40/nabil/LimbFit_c/stage

setenv DRMS_ROOT_DIR          /homef/nabil/JSOC-orig
setenv DRMS_INSTALL_DIR       /homef/nabil/JSOC-orig
setenv DRMS_BINS_INSTALL_DIR  /homef/nabil/JSOC-orig/bin/linux_avx2
setenv DRMS_LIBS_INSTALL_DIR  /homef/nabil/JSOC-orig/lib/linux_avx2
setenv DRMS_INCS_INSTALL_DIR  /homef/nabil/JSOC-orig/include
setenv DRMS_PARAMS_INSTALL_DIR /homef/nabil/JSOC-orig/include/base
setenv DRMS_SCRS_INSTALL_DIR  /homef/nabil/JSOC-orig/scripts
setenv DRMS_SRC_INSTALL_DIR   /homef/nabil/JSOC-orig/src
