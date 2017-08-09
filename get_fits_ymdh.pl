#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
my $JSOC_MACHINE = $ENV{JSOC_MACHINE};
my ($yr, $mon, $hr, $da, $dur, $inpnam, $outnam, @files, $n, $wl);
my $outroot = '/tmp28/jps/LimbFit/fits';
my $path_dir = '/tmp28/jps/LimbFit/paths';
my $stage_dir = '/tmp28/jps/LimbFit/stage';
my $pnam = '/home/jps/LimbFit/get_fits.csh';
my $log = '/tmp28/jps/LimbFit/logs';
my $qsub = '/SGE/bin/lx24-amd64/qsub2';

GetOptions(
           "outroot=s" => \$outroot,
           "path_dir=s" => \$path_dir,
           "stage_dir=s" => \$stage_dir,
           "year=i" => \$yr,
           "month=i" => \$mon,
           "day=i" => \$da,
           "hour=i" => \$hr,
           "dur=s" => \$dur
          );
my $outdir = sprintf "$outroot/$yr/%.2d/%.2d", $mon, $da;
`mkdir -p $outdir` unless -e $outdir;
foreach $wl (94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500) {
  my $run = sprintf "$yr%.2d%.2d_%.2d_%.4d", $mon, $da, $hr, $wl;
  $inpnam = sprintf "$path_dir/$yr/%.2d/%.2d/$run.images", $mon, $da;
  $ENV{FILES_FILE} = $inpnam;
  $outnam = "$outdir/$run.limb";
  $ENV{OUT_FILE} = $outnam;
  my $result = `/home/jps/bin/ana limbcompute_driver.ana < /dev/null`;
}
