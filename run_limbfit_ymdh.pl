#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::LimbfitCommand
  qw(dated_dir limb_filename limbfit_command limbfit_query run_limbfit_to_file wavelength_sum);
use Getopt::Long;
use File::Path qw(make_path);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{SUMSERVER}               = $cfg->{sumserver};
local $ENV{SGE_ROOT}                = $cfg->{sge_root};
local $ENV{DRMS_ROOT_DIR}           = $cfg->{drms_root_dir};
local $ENV{DRMS_PARAMS_INSTALL_DIR} = $cfg->{drms_params_install_dir};
local $ENV{DRMS_SCRS_INSTALL_DIR}   = $cfg->{drms_scrs_install_dir};
local $ENV{DRMS_SRC_INSTALL_DIR}    = $cfg->{drms_src_install_dir};

my ( $yr, $mo, $hr, $da, $dur );
my $filt    = $cfg->{drms_filter};
my $outroot = $cfg->{fits_root};
my $series  = $cfg->{lev1_series};
my $dry_run = 0;
my $plots   = 0;

GetOptions(
  'filter=s'  => \$filt,
  'series=s'  => \$series,
  'outroot=s' => \$outroot,
  'year=i'    => \$yr,
  'month=i'   => \$mo,
  'day=i'     => \$da,
  'hour=i'    => \$hr,
  'dur=s'     => \$dur,
  'dry-run'   => \$dry_run,
  'plots!'    => \$plots,
);
$dur //= '3h';

sub _status_text ($status) {
  return 'signal ' . ( $status & 127 ) if $status & 127;
  return 'exit ' .   ( $status >> 8 );
}

my $outdir = dated_dir( $outroot, $yr, $mo, $da );
make_path( $outdir, { chmod => oct('755') } ) unless -d $outdir;

my $attempted  = 0;
my $succeeded  = 0;
my $failed_any = 0;

for my $w ( @{ $cfg->{wl} } ) {
  $attempted++;
  my $outnam = limb_filename( $yr, $mo, $da, $hr, $w );
  my $qs     = limbfit_query(
    series     => $series,
    year       => $yr,
    month      => $mo,
    day        => $da,
    hour       => $hr,
    duration   => $dur,
    wavelength => $w,
    filter     => $filt,
  );
  my $sum     = wavelength_sum($w);
  my $outpath = "$outdir/$outnam";
  my $cmd     = limbfit_command(
    limbfit_exe => $cfg->{limbfit_exe},
    query       => $qs,
    sum         => $sum,
    outpath     => $outpath
  );

  if ($dry_run) {
    print "$cmd\n";
    next;
  }

  my $status = run_limbfit_to_file(
    limbfit_exe => $cfg->{limbfit_exe},
    query       => $qs,
    sum         => $sum,
    outpath     => $outpath,
  );

  if ( $status != 0 ) {
    warn "limbfit_aia failed for ${w}A at ${yr}-${mo}-${da} ${hr}:00 UTC ("
      . _status_text($status) . ")\n";
    unlink $outpath;
    $failed_any = 1;
    next;
  }

  if ( !-e $outpath || !-s $outpath ) {
    my $detail = -e $outpath ? "empty output file\n" : "no output file\n";
    warn "limbfit_aia failed for ${w}A at ${yr}-${mo}-${da} ${hr}:00 UTC ($detail)";
    unlink $outpath if -e $outpath;
    $failed_any = 1;
    next;
  }

  $succeeded++;
}

exit 0 if $dry_run;
die "limbfit_aia failed for every wavelength at ${yr}-${mo}-${da} ${hr}:00 UTC\n"
  if $attempted > 0 && $succeeded == 0 && $failed_any;
exit 0;
