#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(configure_drms_environment show_info_count);
use AIALimbfit::Inventory   qw(limb_path);
use AIALimbfit::LimbfitCommand
  qw(limbfit_command limbfit_query plot_command run_limbfit_to_file validate_limbfit_args wavelength_sum);
use File::Basename qw(dirname);
use Getopt::Long;
use File::Path qw(make_path);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

my ( $yr, $mo, $hr, $da );
my $filt         = $cfg->{drms_filter};
my $quality_filt = $cfg->{drms_quality_filter} // q{};
my $show_info    = $cfg->{show_info};
my ( $outroot, $series, $wavelength );
my $dry_run = 0;
my $plots;

GetOptions(
  'series=s'  => \$series,
  'outroot=s' => \$outroot,
  'year=i'    => \$yr,
  'month=i'   => \$mo,
  'day=i'     => \$da,
  'hour=i'    => \$hr,
  'wavel=i'   => \$wavelength,
  'dry-run'   => \$dry_run,
  'plots!'    => \$plots,
) or die "Invalid options\n";
$outroot //= defined $wavelength ? "$cfg->{check_gaps_dir}/limb" : $cfg->{fits_root};
$series  //= defined $wavelength ? 'aia.lev1'                    : $cfg->{lev1_series};
$plots   //= defined $wavelength ? 1                             : 0;
validate_limbfit_args(
  year        => $yr,
  month       => $mo,
  day         => $da,
  hour        => $hr,
  wavelength  => $wavelength,
  wavelengths => $cfg->{wl},
);

sub _status_text ($status) {
  return "exec error: $!" if $status == -1;
  return 'signal ' . ( $status & 127 ) if $status & 127;
  return 'exit ' . ( $status >> 8 );
}

my $outdir = dirname( limb_path( $outroot, $yr, $mo, $da, $hr, $wavelength // $cfg->{wl}[0] ) );
make_path( $outdir, { chmod => oct('755') } ) if !$dry_run && !-d $outdir;

my $attempted = 0;
my $succeeded = 0;
my @failed;
my @skipped;
my @wavelengths = defined $wavelength ? ($wavelength) : @{ $cfg->{wl} };
my $slot        = sprintf '%04d-%02d-%02dT%02d:00Z', $yr, $mo, $da, $hr;

for my $w (@wavelengths) {
  my %query_args = (
    series     => $series,
    year       => $yr,
    month      => $mo,
    day        => $da,
    hour       => $hr,
    duration   => $cfg->{cadence_h} . 'h',
    wavelength => $w,
  );
  my $source_qs = limbfit_query( %query_args, filter => $filt );
  my $qs        = limbfit_query( %query_args, filter => $filt . $quality_filt );
  my $sum       = wavelength_sum($w);
  my $outpath   = limb_path( $outroot, $yr, $mo, $da, $hr, $w );
  my $cmd       = limbfit_command(
    limbfit_exe => $cfg->{limbfit_exe},
    query       => $qs,
    sum         => $sum,
    outpath     => $outpath
  );

  if ($dry_run) {
    print "$cmd\n";
    print join( q{ }, plot_command( plotter => "$RealBin/plot_limb.py", limb_path => $outpath ) ),
      "\n"
      if $plots;
    next;
  }

  if ( length $quality_filt && show_info_count( $show_info, $qs ) == 0 ) {
    my $source_count = show_info_count( $show_info, $source_qs );
    my $reason =
      $source_count
      ? "all $source_count source records rejected by data-quality filter"
      : 'no source records';
    warn "LIMBFIT SKIP slot=$slot wavelength=${w}A reason=$reason\n";
    unlink $outpath if -e $outpath;
    push @skipped, $w;
    next;
  }

  $attempted++;
  warn "LIMBFIT START slot=$slot wavelength=${w}A output=$outpath\n";
  my $status = run_limbfit_to_file(
    limbfit_exe => $cfg->{limbfit_exe},
    query       => $qs,
    sum         => $sum,
    outpath     => $outpath,
  );

  if ( $status != 0 ) {
    warn "LIMBFIT FAIL slot=$slot wavelength=${w}A status=" . _status_text($status) . "\n";
    unlink $outpath;
    push @failed, $w;
    next;
  }

  if ( !-e $outpath || !-s $outpath ) {
    my $detail = -e $outpath ? 'empty output file' : 'no output file';
    warn "LIMBFIT FAIL slot=$slot wavelength=${w}A status=$detail\n";
    unlink $outpath if -e $outpath;
    push @failed, $w;
    next;
  }

  $succeeded++;
  warn "LIMBFIT OK slot=$slot wavelength=${w}A output=$outpath\n";
  system( plot_command( plotter => "$RealBin/plot_limb.py", limb_path => $outpath ) ) == 0
    or warn "plot_limb.py failed for $outpath: exit=$?\n"
    if $plots;
}

exit 0 if $dry_run;
rmdir $outdir;
my $failed  = @failed  ? join( q{,}, map { $_ . q{A} } @failed )  : 'none';
my $skipped = @skipped ? join( q{,}, map { $_ . q{A} } @skipped ) : 'none';
warn
"LIMBFIT SUMMARY slot=$slot succeeded=$succeeded attempted=$attempted failed=$failed skipped=$skipped\n";
if ( @failed || @skipped ) {
  warn "Incomplete limb set for $slot\n";
  exit 1;
}
exit 0;
