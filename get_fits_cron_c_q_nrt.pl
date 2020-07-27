#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
$ENV{TZ} = "UTC";
my $pnam = '/home/jps/git/LimbFit/get_fits_c_q_nrt.csh';
my $log = '/surge40/jps/LimbFit_c/logs_nrt';
my $qsub = '/SGE/bin/lx24-amd64/qsub2';
my ($sec, $mn, $hr, $da, $mo, $yr, $wdy, $yd, $isd) = gmtime(time-79200);
$sec = $mn = 0; $yr += 1900; $mo++;
GetOptions(
           "year=i" => \$yr,
           "month=i" => \$mo,
           "day=i" => \$da,
           "hour=i" => \$hr,
          );
exit if $hr % 3;
my $run = sprintf "$yr%.2d%.2d_%.2d", $mo, $da, $hr;
my $pcall = "$pnam $yr $mo $da $hr 3h";
my $result = `$qsub -q k.q -o $log/$run.log -e $log/$run.err $pcall`;
