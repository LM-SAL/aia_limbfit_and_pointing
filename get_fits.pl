#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
my $JSOC_MACHINE = $ENV{JSOC_MACHINE};
my ($yr, $mon, $hr, $da, $outnam, @files, $n);
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
          );
if (opendir SDH, $stage_dir) {
  @files = sort grep { /images$/ } readdir SDH;
  closedir SDH;
} else { exit; }
foreach my $file (@files) {
  my @run = split /\./, $file;
  my @fields = split /_/, $run[0];
  $yr = substr $fields[0], 0, 4; $mon = substr $fields[0], 4, 2;
  $da = substr $fields[0], 6, 2; $hr = $fields[1];
  my $outdir = "$outroot/$yr/$mon/$da";
  `mkdir -p $outdir` unless -e $outdir;
  $outnam = "$run[0].limb";
  my $pcall = "$pnam '$stage_dir/$file' '$outdir/$outnam'";
  my $result = `$qsub -q k.q -o $log/$run[0].log -e $log/$run[0].err $pcall`;
  print "Result: '$result'.\n";
  last if ++$n>9;
}
