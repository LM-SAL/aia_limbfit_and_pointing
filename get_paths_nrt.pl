#!/usr/bin/perl
use strict;
use warnings;
use File::Copy;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
my $JSOC_MACHINE = $ENV{JSOC_MACHINE};
my ($yr, $mon, $hr, $da, $month, $year, $outnam, $qs, $wl, $stage, @lines);
my $seg = 'image_lev1';
my $series = 'aia.lev1_nrt2';
my $show_info = "/home/jsoc/cvs/Development/JSOC/bin/$JSOC_MACHINE/show_info";
my $path_dir = '/tmp28/jsocprod/jps/LimbFit/paths_nrt';
my $stage_dir = '/tmp28/jsocprod/jps/LimbFit/stage_nrt';
my $filt = '';
my $dur = '3h';
my $kw = 'IMG_TYPE,ACS_MODE';
my $t0 = time;
($hr, $da, $month, $year) = (gmtime($t0))[2, 3, 4, 5];
$yr = $year + 1900; $mon = $month + 1; $hr = 3*int($hr/3);
GetOptions(
           "year=i" => \$yr,
           "month=i" => \$mon,
           "day=i" => \$da,
           "hour=i" => \$hr,
           "dur=s" => \$dur,
           "filt=s" => \$filt,
           "path_dir=s" => \$path_dir,
           "seg=s" => \$seg,
           "series=s" => \$series,
           "stage!" => \$stage
          );

my $outdir = sprintf "$path_dir/$yr/%2.2d/%2.2d", $mon, $da;
`mkdir -p $outdir` unless -e $outdir;
for $wl (94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500) {
  $outnam = sprintf "$outdir/$yr%2.2d%2.2d_%2.2d_%4.4d.images",
               $mon, $da, $hr, $wl;
  $qs = "$series\[$yr.$mon.${da}_$hr/$dur][?WAVELNTH=$wl?]$filt";
  @lines = `$show_info -q -P key=$kw seg=$seg $qs`;
  save_paths($outnam, @lines);
  copy $outnam, $stage_dir if $stage;
}

sub save_paths
{
  my ($out, @lines) = @_;
  open(my $fhout, ">", $out) or die "$0: can't open $out for writing: $!";
  for (@lines) {
    my ($type, $mode, $path) = split;
    print $fhout "$path\n" if $type =~ /LIGHT/ and $mode =~ /SCIENCE/;
  }
  close $fhout;
}
