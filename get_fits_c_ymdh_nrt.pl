#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
my $JSOC_MACHINE = $ENV{JSOC_MACHINE};
my ($yr, $mo, $hr, $da, $dur, $inpnam, $outnam, $qs, @files, $n, $wl, $sum);
my $outroot = '/tmp29/jps/LimbFit_c/fits_nrt';
my $series = 'aia.lev1_nrt2';

GetOptions(
           "series=s" => \$series,
           "outroot=s" => \$outroot,
           "year=i" => \$yr,
           "month=i" => \$mo,
           "day=i" => \$da,
           "hour=i" => \$hr,
           "dur=s" => \$dur
          );
my $outdir = sprintf "$outroot/$yr/%.2d/%.2d", $mo, $da;
`mkdir -p $outdir` unless -e $outdir;
for my $w (94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500) {
  $outnam = sprintf "$yr%.2d%.2d_%.2d_%.4d.limb", $mo, $da, $hr, $w;
  $qs = sprintf "$series\[$yr.%.2d.%.2d_%.2d/$dur]\[?WAVELNTH=$w?]", $mo, $da, $hr;
  $sum = 1;
  $sum = 3 if $w < 4000;
  $sum = 5 if $w < 1500;
  system "/home/jps/bin/limbfit_aia dsinp=$qs sum=$sum > $outdir/$outnam";
}
