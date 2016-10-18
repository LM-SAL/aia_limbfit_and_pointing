#!/usr/bin/perl
use strict;
use warnings;
use File::Copy;
use Getopt::Long;

$ENV{SUMSERVER} = "k1";
$ENV{SGE_ROOT} = "/SGE";
my $JSOC_MACHINE = $ENV{JSOC_MACHINE};
my ($yr, $mon, $hr, $da, $month, $year, $outnam, $qs, $wl, $limbfit);
my $show_info = "/home/jsoc/cvs/Development/JSOC/bin/$JSOC_MACHINE/show_info";
my $path_dir = '/tmp28/jps/LimbFit/paths';
my $stage_dir = '/tmp28/jps/LimbFit/stage';
my $dur = '3h';
my $t0 = time;
($hr, $da, $month, $year) = (gmtime($t0))[2, 3, 4, 5];
$yr = $year + 1900; $mon = $month + 1; $hr = 3*int($hr/3);
GetOptions(
           "year=i" => \$yr,
           "month=i" => \$mon,
           "day=i" => \$da,
           "hour=i" => \$hr,
           "dur=s" => \$dur,
           "limbfit!" => \$limbfit
          );

my $outdir = sprintf "$path_dir/$yr/%2.2d/%2.2d", $mon, $da;
`mkdir -p $outdir` unless -e $outdir;
for $wl (94, 131, 171, 193, 211, 304, 335) {
  $outnam = sprintf "$outdir/$yr%2.2d%2.2d_%2.2d_%4.4d.images",
               $mon, $da, $hr, $wl;
  $qs = "aia.lev1_euv_12s[$yr.$mon.${da}_$hr/$dur\@2m][$wl]";
  `$show_info -q -P seg=image $qs > $outnam`;
   copy $outnam, $stage_dir if $limbfit;
}
for $wl (1600, 1700) {
  $outnam = sprintf "$outdir/$yr%2.2d%2.2d_%2.2d_%4.4d.images",
               $mon, $da, $hr, $wl;
  $qs = "aia.lev1_uv_24s[$yr.$mon.${da}_$hr/$dur\@2m][$wl]";
  `$show_info -q -P seg=image $qs > $outnam`;
   copy $outnam, $stage_dir if $limbfit;
}
$wl = 4500;
$outnam = sprintf "$outdir/$yr%2.2d%2.2d_%2.2d_%4.4d.images",
             $mon, $da, $hr, $wl;
$qs = "aia.lev1_vis_1h[$yr.$mon.${da}_$hr/$dur][$wl]";
`$show_info -q -P seg=image $qs > $outnam`;
copy $outnam, $stage_dir if $limbfit;
