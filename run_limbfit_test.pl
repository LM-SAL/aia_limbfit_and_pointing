#!/home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::LimbfitCommand qw(
  dated_dir
  limb_filename
  limbfit_command
  limbfit_query
  plot_command
  plot_path
  wavelength_sum
);
use Getopt::Long;
use File::Path qw(make_path);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{SUMSERVER}               = $cfg->{sumserver};
local $ENV{SGE_ROOT}                = $cfg->{sge_root};
local $ENV{DRMS_ROOT_DIR}           = $cfg->{drms_root_dir};
local $ENV{DRMS_PARAMS_INSTALL_DIR} = $cfg->{drms_params_install_dir};
local $ENV{DRMS_SCRS_INSTALL_DIR}   = $cfg->{drms_scrs_install_dir};
local $ENV{DRMS_SRC_INSTALL_DIR}    = $cfg->{drms_src_install_dir};

my ( $yr, $mo, $hr, $da, $dur );
my $w       = 304;
my $filt    = $cfg->{drms_filter};
my $outroot = $cfg->{test_fits_root};
my $series  = 'aia.lev1';
my $plots   = 1;
my $dry_run = 0;

GetOptions(
  'filter=s'  => \$filt,
  'series=s'  => \$series,
  'outroot=s' => \$outroot,
  'year=i'    => \$yr,
  'month=i'   => \$mo,
  'day=i'     => \$da,
  'hour=i'    => \$hr,
  'dur=s'     => \$dur,
  'wavel=i'   => \$w,
  'plots!'    => \$plots,
  'dry-run'   => \$dry_run,
);
$dur //= '3h';

my $outdir = dated_dir( $outroot, $yr, $mo, $da );
make_path( $outdir, { chmod => oct('755') } ) unless -d $outdir;

sub _generate_plot {
  my ($limb) = @_;
  return unless -s $limb;

  system( plot_command( plotter => "$RealBin/plot_limb.py", limb_path => $limb, perl => $^X ) ) == 0
    or warn "plot_limb.py failed for $limb: exit=$?\n";
  return;
}

my $outnam = limb_filename( $yr, $mo, $da, $hr, $w );
my $qs     = limbfit_query(
  series => $series, year => $yr, month => $mo, day => $da, hour => $hr,
  duration => $dur, wavelength => $w, filter => $filt,
);
my $sum     = wavelength_sum($w);
my $outpath = "$outdir/$outnam";
my $cmd     = limbfit_command( limbfit_exe => $cfg->{limbfit_exe}, query => $qs, sum => $sum, outpath => $outpath );

if ($dry_run) {
  print "$cmd\n";
  print join( ' ', plot_command( plotter => "$RealBin/plot_limb.py", limb_path => $outpath, perl => $^X ) ), "\n" if $plots;
  exit 0;
}

system($cmd) == 0
  or die "limbfit_aia failed for ${w}A\n";

_generate_plot($outpath) if $plots;
