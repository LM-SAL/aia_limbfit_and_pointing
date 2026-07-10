#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(validate_drms_runtime show_info_lines);
use AIALimbfit::Inventory   qw(expected_limb_path);
use AIALimbfit::Slot        qw(tstr2ts ts2ymdh);
use Getopt::Long;
use Scalar::Util qw(looks_like_number);
use Time::Local;
use File::Basename qw(dirname);
use File::Copy     qw(copy);
use File::Path     qw(make_path);

# Query aia.master_pointing3h (or another pointing series) and report:
#   - Temporal gaps: missing slots between consecutive records.
#     Repair mode stages gaps that are a multiple of the cadence.
#     Non-multiple gaps (corrupted T_STOP) are always left as-is.
#   - Wavelength gaps: existing records with NaN/MISSING per-wavelength values.
#     A patch.txt report is written; repair mode regenerates and installs files.
#
#   -repair   stage repairs for an explicit date or range.
#   -dry-run  with -repair, print commands without running them.
#   -plots    only regenerate plots for existing .limb files.
#
# When no start date is given the script defaults to 2010-11-01.
# When no end date is given the script defaults to 7 days ago.

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{TZ}        = $cfg->{tz};
local $ENV{SUMSERVER} = $ENV{SUMSERVER} // $cfg->{sumserver};
my $drms_bin_dir = dirname( $cfg->{show_info} );
my $drms_base    = dirname( dirname($drms_bin_dir) );
local $ENV{DRMS_ROOT_DIR}           = $ENV{DRMS_ROOT_DIR}           // $drms_base;
local $ENV{DRMS_INSTALL_DIR}        = $ENV{DRMS_INSTALL_DIR}        // $drms_base;
local $ENV{DRMS_BINS_INSTALL_DIR}   = $ENV{DRMS_BINS_INSTALL_DIR}   // $drms_bin_dir;
local $ENV{DRMS_LIBS_INSTALL_DIR}   = $ENV{DRMS_LIBS_INSTALL_DIR}   // "$drms_base/lib/linux_avx2";
local $ENV{DRMS_INCS_INSTALL_DIR}   = $ENV{DRMS_INCS_INSTALL_DIR}   // "$drms_base/include";
local $ENV{DRMS_PARAMS_INSTALL_DIR} = $ENV{DRMS_PARAMS_INSTALL_DIR} // "$drms_base/include/base";
local $ENV{DRMS_SCRS_INSTALL_DIR}   = $ENV{DRMS_SCRS_INSTALL_DIR}   // "$drms_base/scripts";
local $ENV{DRMS_SRC_INSTALL_DIR}    = $ENV{DRMS_SRC_INSTALL_DIR}    // "$drms_base/src";

my $show_info = $cfg->{show_info};
my $plot_limb = $cfg->{plot_limb}        // "$RealBin/plot_limb.py";
my $lf2mpr    = $cfg->{lf2mpr_nrt}       // "$RealBin/lf2mpr_nrt.pdl";
my $run_ymdh  = $cfg->{run_limbfit_ymdh} // "$RealBin/run_limbfit_ymdh.pl";

my $series       = $cfg->{mpt_series};
my $cadence_h    = $cfg->{cadence_h} // 3;
my $cadence_s    = $cadence_h * 3600;
my $nan_sentinel = $cfg->{nan_sentinel};
my $fits_root    = $cfg->{fits_root};
my @wl           = @{ $cfg->{wl} };

my ( $yr, $mo, $da, $eyr, $emo, $eda );
my $start_explicit = 0;
my $end_explicit   = 0;

my $plots_only   = 0;
my $dry_run      = 0;
my $repair       = 0;
my $image_series = undef;
my $start_parts  = 0;

GetOptions(
  'year=i'         => sub { $yr  = $_[1]; $start_explicit = 1; $start_parts++ },
  'month=i'        => sub { $mo  = $_[1]; $start_explicit = 1; $start_parts++ },
  'day=i'          => sub { $da  = $_[1]; $start_explicit = 1; $start_parts++ },
  'end_year=i'     => sub { $eyr = $_[1]; $end_explicit   = 1; },
  'end_month=i'    => sub { $emo = $_[1]; $end_explicit   = 1; },
  'end_day=i'      => sub { $eda = $_[1]; $end_explicit   = 1; },
  'series=s'       => \$series,
  'image_series=s' => \$image_series,
  'dry-run'        => \$dry_run,
  'repair'         => \$repair,
  'plots'          => \$plots_only,
) or die "Invalid options\n";
die "--dry-run requires --repair\n"                           if $dry_run && !$repair;
die "--repair requires explicit --year, --month, and --day\n" if $repair  && $start_parts != 3;

my ( undef, undef, undef, undef, $today_m, $today_y ) = gmtime time;
$today_y += 1900;
$today_m++;

if ($start_explicit) {
  $yr //= $today_y;
  $mo //= 1;
  $da //= 1;
}
else {
  $yr = 2010;
  $mo = 11;
  $da = 1;
}

if ($end_explicit) {
  $eyr //= $today_y;
  $emo //= 12;
  $eda //= 31;
}
elsif ( $start_parts == 3 ) {
  $eyr = $yr;
  $emo = $mo;
  $eda = $da;
}
else {
  # Default end date is 7 days ago (ignore last week, which may be incomplete)
  my ( undef, undef, undef, $end_d, $end_m, $end_y ) = gmtime( time - 7 * 86_400 );
  $eyr = $end_y + 1900;
  $emo = $end_m + 1;
  $eda = $end_d;
}

if ($plots_only) {
  _plot_all_in_range( $yr, $mo, $da, $eyr, $emo, $eda );
  exit 0;
}

validate_drms_runtime($show_info);

make_path( $cfg->{check_gaps_dir}, { chmod => oct('755') } ) unless -d $cfg->{check_gaps_dir};
my $patch_file = "$cfg->{check_gaps_dir}/patch.txt";
open my $patch_fh, '>', $patch_file or die "Cannot open patch file '$patch_file': $!\n";

printf "# Checking %s from %d-%.2d-%.2d to %d-%.2d-%.2d\n", $series, $yr, $mo, $da, $eyr, $emo,
  $eda;

my @keys = qw(T_START T_STOP);
for my $w (@wl) {
  push @keys, sprintf 'A_%.3d_X0', $w;
  push @keys, sprintf 'A_%.3d_Y0', $w;
}
my $keylist = join q{,}, @keys;

my $qt = sprintf '%s[%d.%.2d.%.2d_00:00-%d.%.2d.%.2d_23:59]',
  $series, $yr, $mo, $da, $eyr, $emo, $eda;
my @lines = show_info_lines( $show_info, '-q', "key=$keylist", $qt );

chomp @lines;
@lines = grep { /\S/ } @lines;

die "No records found for $qt\n" if @lines == 0;

my @recs;
for my $line (@lines) {
  my @fields = split /\s+/, $line;
  next if @fields < 2;
  my ( $t_start, $t_stop, @xyvals ) = @fields;

  my @missing_wl;
  for my $i ( 0 .. $#wl ) {
    my $x  = $xyvals[ $i * 2 ];
    my $yc = $xyvals[ $i * 2 + 1 ];
    if ( _is_bad_value( $x, $nan_sentinel ) || _is_bad_value( $yc, $nan_sentinel ) ) {
      push @missing_wl, $wl[$i];
    }
  }

  my $start = tstr2ts($t_start);
  my $stop  = tstr2ts($t_stop);
  next unless defined $start && defined $stop;
  push @recs,
    {
    start         => $start,
    stop          => $stop,
    t_start       => $t_start,
    t_stop        => $t_stop,
    missing_wl    => \@missing_wl,
    missing_count => scalar @missing_wl,
    };
}

@recs = sort { $a->{start} <=> $b->{start} } @recs;

my $epsilon           = 2;
my $temporal          = 0;
my $wl_gaps           = 0;
my $backfills         = 0;
my @backfill_failures = ();

for my $i ( 1 .. $#recs ) {
  my $prev = $recs[ $i - 1 ];
  my $cur  = $recs[$i];

  # Compare T_START to T_START so records with wrong T_STOP (e.g. 6h spans)
  # don't produce false overlaps or missed gaps.
  my $diff = $cur->{start} - $prev->{start};
  next if $diff < $cadence_s - $epsilon;

  next if $diff < $cadence_s + $epsilon;    # exactly one cadence: contiguous

  printf "TEMPORAL GAP  %s  ->  %s  (%.2f h)\n", $prev->{t_start}, $cur->{t_start}, $diff / 3600.0;
  $temporal++;

  next if $diff % $cadence_s > $epsilon;

  $backfills += _backfill_slot_range( $prev->{start} + $cadence_s, $cur->{start} ) if $repair;
}

for my $rec (@recs) {
  next if $rec->{missing_count} == 0;

  printf {$patch_fh} "%s  %d  NaN  NaN\n", $rec->{t_start}, $_ for @{ $rec->{missing_wl} };

  printf "MISSING WAVELENGTHS  %s:  %s\n", $rec->{t_start}, join ', ', @{ $rec->{missing_wl} };

  if ($repair) {
    my ( $yy, $mm, $dd, $hh ) = ts2ymdh( $rec->{start} );
    for my $wl ( @{ $rec->{missing_wl} } ) {
      my $fn = expected_limb_path( "$cfg->{check_gaps_dir}/limb", $yy, $mm, $dd, $hh, $wl );
      if ( -e $fn && -s $fn ) {
        print "# Skipping $yy-$mm-$dd $hh:00 $wl - limb file already exists\n";
        if ($dry_run) {
          print "# Would install $fn after review\n";
          next;
        }
        _generate_plot( $yy, $mm, $dd, $hh, $wl, $fn );
        _install_limb( $fn, $yy, $mm, $dd, $hh, $wl );
        next;
      }
      if ( -z $fn ) {
        if ($dry_run) {
          print "# Would remove empty limb file $fn\n";
        }
        else {
          print "# Removing empty limb file $fn\n";
          unlink $fn;
        }
      }
      _exec_test_limbfit( $yy, $mm, $dd, $hh, $wl );
    }
    _reduce_limb_set( $fits_root, $yy, $mm, $dd, $hh );
  }
  $wl_gaps++;
}

close $patch_fh or warn "Cannot close patch file '$patch_file': $!\n";

if ( $temporal == 0 && $wl_gaps == 0 ) {
  print "No gaps detected in $qt\n";
}
else {
  print "---\n";
  print "Temporal gaps: $temporal\n"   if $temporal;
  print "Wavelength gaps: $wl_gaps\n"  if $wl_gaps;
  print "Backfill slots: $backfills\n" if $backfills;
  print 'Backfill failures: ', scalar @backfill_failures, "\n" if @backfill_failures;
  if (@backfill_failures) {
    print "Failed backfill slots:\n";
    for my $failure (@backfill_failures) {
      printf "  %d-%.2d-%.2d %.2d:00 UTC: %s\n",
        $failure->{year}, $failure->{month}, $failure->{day}, $failure->{hour}, $failure->{reason};
    }
  }
}

if ( $temporal || $wl_gaps ) {
  if ($repair) {
    print "\n# Staged outputs in $cfg->{check_gaps_dir}\n";
    print "#   masterpoint  -> $cfg->{check_gaps_dir}/stage/\n";
    print "# Inspect the staged masterpoints and diagnostic plots, then commit with:\n";
    print "#   update3h_mpt.pl -srcdir=$cfg->{check_gaps_dir}/stage\n";
  }
  else {
    print "\n# Report only; no limb fits or repairs were run.\n";
    print
      "# Preview an approved date or range with -repair -dry-run, then rerun without -dry-run.\n";
    print "# Wavelength report: $patch_file\n" if $wl_gaps;
  }
}

sub _is_bad_value ( $v, $sentinel ) {
  return 1 unless defined $v && length $v;
  return 1 if $v =~ /^(?i:nan|missing)$/;
  return 1 if defined $sentinel && $v eq $sentinel;
  return 1
    if defined $sentinel
    && looks_like_number($v)
    && looks_like_number($sentinel)
    && 0 + $v == 0 + $sentinel;
  return 0;
}

sub _backfill_slot_range ( $start, $stop ) {
  my $count = 0;
  my $t     = $start;
  while ( $t < $stop ) {
    my ( $yy, $mm, $dd, $hh ) = ts2ymdh($t);
    try {
      _maybe_exec_limbfit( $yy, $mm, $dd, $hh );
    }
    catch ($e) {
      chomp $e;
      warn "Backfill failed for $yy-$mm-$dd $hh:00 UTC; continuing: $e\n";
      push @backfill_failures,
        {
        year   => $yy,
        month  => $mm,
        day    => $dd,
        hour   => $hh,
        reason => $e,
        };
    }
    $t += $cadence_s;
    $count++;
  }
  return $count;
}

sub _slot_has_limb_files ( $y, $m, $d, $h, $quiet = 0 ) {
  my $dir = sprintf "$cfg->{check_gaps_dir}/limb/%d/%.2d/%.2d", $y, $m, $d;
  return 0 unless -d $dir;

  my @missing;
  for my $wl (@wl) {
    my $f = expected_limb_path( "$cfg->{check_gaps_dir}/limb", $y, $m, $d, $h, $wl );
    if ( -e $f && !-s $f ) {
      if ($dry_run) {
        print "# Would remove empty limb file $f\n";
      }
      else {
        print "# Removing empty limb file $f\n";
        unlink $f;
      }
    }
    push @missing, $wl unless -s $f;
  }
  if (@missing) {
    print "# Existing limb set is incomplete for $y-$m-$d $h:00; regenerating slot\n" unless $quiet;
    return 0;
  }
  return 1;
}

sub _maybe_exec_limbfit ( $y, $m, $d, $h ) {
  if ( _slot_has_limb_files( $y, $m, $d, $h ) ) {
    print "# Skipping $y-$m-$d $h:00 - limb files already exist\n";
    return;
  }
  _exec_limbfit( $y, $m, $d, $h );
  return;
}

sub _generate_plot ( $y, $m, $d, $h, $wl, $limb_path ) {
  my $limb = $limb_path;
  ( my $plot = $limb ) =~ s/[.]limb$/.png/;

  if ( !-e $limb || !-s $limb ) {
    print "# plot SKIP_MISSING  $limb\n";
    return;
  }
  print "# plot START  $limb  ->  $plot\n";
  system( $plot_limb, $limb, '-o', $plot, '--perl', $^X );
  if ( $? == 0 ) {
    print "# plot OK  $limb  ->  $plot\n";
  }
  else {
    print "# plot FAIL  $limb  ->  $plot\n";
  }
  return;
}

sub _plot_all_in_range ( $y0, $m0, $d0, $y1, $m1, $d1 ) {
  my $start_ts = timegm( 0,  0,  0,  $d0, $m0 - 1, $y0 );
  my $end_ts   = timegm( 59, 59, 23, $d1, $m1 - 1, $y1 );
  my $base     = "$cfg->{check_gaps_dir}/limb";

  if ( !-d $base ) {
    warn "Limb directory not found: $base\n";
    return 0;
  }

  ## no critic (RegularExpressions::ProhibitComplexRegexes)
  my $re = qr{
    (\d{4}) / (\d{2}) / (\d{2}) /
    (\d{4}) (\d{2}) (\d{2}) _
    (\d{2}) _ (\d{4}) [.] limb $
  }x;
  my @files = glob "$base/*/*/*/*.limb";
  my $count = 0;
  for my $f ( sort @files ) {
    next unless $f =~ $re;
    my ( $y, $m, $d, $h, $wl ) = ( $1, $2, $3, $7, $8 );
    my $ts = timegm( 0, 0, $h, $d, $m - 1, $y );
    next if $ts < $start_ts || $ts > $end_ts;
    _generate_plot( $y, $m, $d, $h, $wl, $f );
    $count++;
  }
  print "# Plotted $count existing limb files\n";
  return $count;
}

sub _exec_test_limbfit ( $y, $m, $d, $h, $wl ) {
  my $limb_dir = "$cfg->{check_gaps_dir}/limb";
  my @cmd      = (
    $^X,         "$run_ymdh", "-year=$y",   "-month=$m",
    "-day=$d",   "-hour=$h",  "-wavel=$wl", "-outroot=$limb_dir",
    '-no-plots', '-series=' . ( $image_series // 'aia.lev1' ),
  );
  print "# @cmd\n";
  return if $dry_run;
  system(@cmd) == 0 or die "run_limbfit_ymdh.pl failed for $y-$m-$d $h:00 ${wl}A: exit=$?\n";

  my $limb = expected_limb_path( $limb_dir, $y, $m, $d, $h, $wl );
  _generate_plot( $y, $m, $d, $h, $wl, $limb );
  _install_limb( $limb, $y, $m, $d, $h, $wl );
  return;
}

sub _exec_limbfit ( $y, $m, $d, $h ) {
  my $limb_dir = "$cfg->{check_gaps_dir}/limb";

  my @series_candidates = defined $image_series ? ($image_series) : do {
    my $slot_epoch = timegm( 0, 0, $h, $d, $m - 1, $y );
    my $nrt2_start = $cfg->{lev1_nrt2_start} ? tstr2ts( $cfg->{lev1_nrt2_start} ) : undef;
    my $skip_nrt2  = defined $nrt2_start && $slot_epoch < $nrt2_start;
    my %seen;
    grep { defined $_ && length $_ && !$seen{$_}++ }
      ( $skip_nrt2 ? () : $cfg->{lev1_series}, 'aia.lev1' );
  };
  my $used_series;

  for my $idx ( 0 .. $#series_candidates ) {
    my $series_name = $series_candidates[$idx];
    my @lf_cmd      = (
      $^X,       "$run_ymdh", "-year=$y",           "-month=$m",
      "-day=$d", "-hour=$h",  "-outroot=$limb_dir", '-no-plots',
      "-series=$series_name",
    );
    print "# @lf_cmd\n";
    return if $dry_run;

    my $status   = system(@lf_cmd);
    my $has_limb = _slot_has_limb_files( $y, $m, $d, $h, 1 );
    if ( $status == 0 && $has_limb ) {
      $used_series = $series_name;
      last;
    }

    my $status_text = $status == -1 ? "exec_error=$!" : "exit=$status";
    if ($has_limb) {
      warn
        "run_limbfit_ymdh.pl returned nonzero for $y-$m-$d $h:00 with $series_name: $status_text\n";
      $used_series = $series_name;
      last;
    }

    my $next_series = $series_candidates[ $idx + 1 ];
    if ( defined $next_series ) {
      print
"# No valid limb outputs for $y-$m-$d $h:00 with $series_name; retrying with $next_series\n";
      next;
    }

    die "No valid limb files generated for $y-$m-$d $h:00 after trying "
      . join( q{, }, @series_candidates ) . "\n";
  }

  _reduce_limb_set( $limb_dir, $y, $m, $d, $h );
  print "# Reduced slot using $used_series\n" if defined $used_series;

  for my $wl ( @{ $cfg->{wl} } ) {
    my $limb = expected_limb_path( $limb_dir, $y, $m, $d, $h, $wl );
    _generate_plot( $y, $m, $d, $h, $wl, $limb );
  }
  return;
}

sub _reduce_limb_set ( $limb_dir, $y, $m, $d, $h ) {
  my $stage_dir = "$cfg->{check_gaps_dir}/stage";
  my @red_cmd   = (
    $^X,        "$lf2mpr",   "-inpdir=$limb_dir", "-outdir=$stage_dir",
    "-year=$y", "-month=$m", "-day=$d",           "-hour=$h",
    '-require-all',
  );
  print "# @red_cmd\n";
  return if $dry_run;
  system(@red_cmd) == 0 or die "lf2mpr_nrt.pdl failed for $y-$m-$d $h:00: exit=$?\n";
  return;
}

sub _install_limb ( $limb, $y, $m, $d, $h, $wl ) {
  die "fits_root is required for -repair\n" unless defined $fits_root;
  my $production = expected_limb_path( $fits_root, $y, $m, $d, $h, $wl );
  make_path( dirname($production), { chmod => oct('755') } ) unless -d dirname($production);
  my $temporary = "$production.$$";
  copy( $limb, $temporary ) or die "Cannot copy '$limb' to '$temporary': $!\n";
  if ( !rename $temporary, $production ) {
    my $error = $!;
    unlink $temporary;
    die "Cannot replace '$production': $error\n";
  }
  print "# installed $production\n";
  return;
}
