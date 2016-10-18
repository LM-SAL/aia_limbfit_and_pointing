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
  my @words = split /\./, $file;
  my @fields = split /_/, $words[0];
  $yr = substr $fields[0], 0, 4; $mon = substr $fields[0], 4, 2;
  $da = substr $fields[0], 6, 2; $hr = $fields[1];
  my $outdir = "$outroot/$yr/$mon/$da";
  `mkdir -p $outdir` unless -e $outdir;
  $outnam = "$words[0].limb";
  $ENV{FILES_FILE} = "$stage_dir/$file";
  $ENV{OUT_FILE} = "$outdir/$outnam";
  print `/home/jps/LimbFit/get_fits.csh`;
  last if ++$n>9;
}
