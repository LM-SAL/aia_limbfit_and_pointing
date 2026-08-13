#!/bin/csh
# Interactive JSOC environment bootstrap. Runtime values live in config.pl.

setenv SUMSERVER k1
setenv TZ        UTC

if ( -f /home/jsoc/.setJSOCenv ) then
  source /home/jsoc/.setJSOCenv
endif
if ( -f /SGE2/default/common/settings.csh ) then
  source /SGE2/default/common/settings.csh
endif

if ( -f /homef/nabil/perl5/perlbrew/etc/cshrc ) then
  source /homef/nabil/perl5/perlbrew/etc/cshrc
else
  echo "Missing perlbrew cshrc: /homef/nabil/perl5/perlbrew/etc/cshrc"
  exit 1
endif
rehash
