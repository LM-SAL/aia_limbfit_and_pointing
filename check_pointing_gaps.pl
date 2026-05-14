#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(validate_drms_runtime show_info_lines);
use AIALimbfit::Slot qw(slot_record_issues tstr2ts ts2ymdh);
use Getopt::Long;
use Scalar::Util qw(looks_like_number);
use Time::Local;
use File::Basename qw(dirname);
use File::Path     qw(make_path);

# Query aia.master_pointing3h (or another pointing series) and report
# temporal gaps between consecutive T_START/T_STOP records,
# plus any wavelengths that are missing within existing records.
#
# Default mode runs the full pipeline: reports gaps, executes back-fill,
# generates plots, and writes a patch file for missing wavelengths.
#   -dry-run   print the back-fill commands without running them.
#   -plots     only regenerate plots for existing .limb files.
#              Skips DRMS queries and limbfit execution.
#
# When no start date is given the script defaults to 2010-11-01.
# When no end date is given the script defaults to 7 days ago.
#
# Usage:
#   ./check_pointing_gaps.pl
#   ./check_pointing_gaps.pl -year=2024 -month=3 -day=1
#   ./check_pointing_gaps.pl -year=2024 -month=3 -plots

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

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{TZ} = $cfg->{tz};
local $ENV{SUMSERVER} = $ENV{SUMSERVER} // $cfg->{sumserver};
my $drms_bin_dir = dirname( $cfg->{show_info} );
my $drms_base    = dirname( dirname($drms_bin_dir) );
local $ENV{DRMS_ROOT_DIR} = $ENV{DRMS_ROOT_DIR} // $drms_base;
local $ENV{DRMS_INSTALL_DIR} = $ENV{DRMS_INSTALL_DIR} // $drms_base;
local $ENV{DRMS_BINS_INSTALL_DIR} = $ENV{DRMS_BINS_INSTALL_DIR} // $drms_bin_dir;
local $ENV{DRMS_LIBS_INSTALL_DIR} = $ENV{DRMS_LIBS_INSTALL_DIR} // "$drms_base/lib/linux_avx2";
local $ENV{DRMS_INCS_INSTALL_DIR} = $ENV{DRMS_INCS_INSTALL_DIR} // "$drms_base/include";
local $ENV{DRMS_PARAMS_INSTALL_DIR} = $ENV{DRMS_PARAMS_INSTALL_DIR} // "$drms_base/include/base";
local $ENV{DRMS_SCRS_INSTALL_DIR} = $ENV{DRMS_SCRS_INSTALL_DIR} // "$drms_base/scripts";
local $ENV{DRMS_SRC_INSTALL_DIR} = $ENV{DRMS_SRC_INSTALL_DIR} // "$drms_base/src";

my $show_info = $cfg->{show_info};
my $plot_limb = $cfg->{plot_limb} // "$RealBin/plot_limb.py";
my $lf2mpr    = $cfg->{lf2mpr_nrt} // "$RealBin/lf2mpr_nrt.pdl";
my $run_ymdh = $cfg->{run_limbfit_ymdh} // "$RealBin/run_limbfit_ymdh.pl";
my $run_test = $cfg->{run_limbfit_test} // "$RealBin/run_limbfit_test.pl";

sub _show_info (@args) {
  return show_info_lines( $show_info, @args );
}

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
my $image_series = undef;

GetOptions(
  'year=i'         => sub { $yr  = $_[1]; $start_explicit = 1; },
  'month=i'        => sub { $mo  = $_[1]; $start_explicit = 1; },
  'day=i'          => sub { $da  = $_[1]; $start_explicit = 1; },
  'end_year=i'     => sub { $eyr = $_[1]; $end_explicit   = 1; },
  'end_month=i'    => sub { $emo = $_[1]; $end_explicit   = 1; },
  'end_day=i'      => sub { $eda = $_[1]; $end_explicit   = 1; },
  'series=s'       => \$series,
  'image_series=s' => \$image_series,
  'dry-run'        => \$dry_run,
  'plots'          => \$plots_only,
);

my ( undef, undef, undef, $today_d, $today_m, $today_y ) = gmtime time;
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

my @keys = qw( T_START T_STOP );
for my $w (@wl) {
  push @keys, sprintf 'A_%.3d_X0', $w;
  push @keys, sprintf 'A_%.3d_Y0', $w;
}
my $keylist = join q{,}, @keys;

my $qt = sprintf '%s[%d.%.2d.%.2d_00:00-%d.%.2d.%.2d_23:59]',
  $series, $yr, $mo, $da, $eyr, $emo, $eda;
my @lines = _show_info( '-q', "key=$keylist", $qt );

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

  push @recs,
    {
    start         => tstr2ts($t_start),
    stop          => tstr2ts($t_stop),
    t_start       => $t_start,
    t_stop        => $t_stop,
    missing_wl    => \@missing_wl,
    missing_count => scalar @missing_wl,
    };
}

@recs = sort { $a->{start} <=> $b->{start} } @recs;

my $epsilon     = 2;
my $temporal    = 0;
my $wl_gaps     = 0;
my $slot_issues = 0;
my $backfills   = 0;
my @backfill_failures = ();

my @gap_recs;
for my $rec (@recs) {
  my @issues = slot_record_issues( $rec, cadence_s => $cadence_s );
  if (@issues) {
    printf "INVALID SLOT  %s  ->  %s  (%s)\n", $rec->{t_start}, $rec->{t_stop}, join ', ', @issues;
    $slot_issues++;

    if ( _is_bridgeable_wrong_duration( $rec, \@issues ) ) {
      $backfills += _backfill_slot_range( $rec->{start}, $rec->{stop} );
      $temporal++;
      push @gap_recs, $rec;
    }
    next;
  }
  push @gap_recs, $rec;
}

for my $i ( 1 .. $#gap_recs ) {
  my $prev = $gap_recs[ $i - 1 ];
  my $cur  = $gap_recs[$i];
  my $diff = $cur->{start} - $prev->{stop};
  if ( $diff < -$epsilon ) {
    printf "OVERLAP  %s  ->  %s  (%.2f h)\n", $prev->{t_stop}, $cur->{t_start}, -$diff / 3600.0;
    $slot_issues++;
    next;
  }
  next if $diff <= $epsilon;

  printf "TEMPORAL GAP  %s  ->  %s  (%.2f h)\n", $prev->{t_stop}, $cur->{t_start}, $diff / 3600.0;

  $backfills += _backfill_slot_range( $prev->{stop}, $cur->{start} );
  $temporal++;
}

for my $rec (@gap_recs) {
  next if $rec->{missing_count} == 0;

  printf {$patch_fh} "%s  %d  NaN  NaN\n", $rec->{t_start}, $_ for @{ $rec->{missing_wl} };

  printf "MISSING WAVELENGTHS  %s:  %s\n", $rec->{t_start}, join ', ', @{ $rec->{missing_wl} };

  my ( $yy, $mm, $dd, $hh ) = ts2ymdh( $rec->{start} );
  for my $wl ( @{ $rec->{missing_wl} } ) {
    my $fn = sprintf "$cfg->{check_gaps_dir}/limb/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb",
      $yy, $mm, $dd, $yy, $mm, $dd, $hh, $wl;
    if ( -e $fn && -s $fn ) {
      print "# Skipping $yy-$mm-$dd $hh:00 $wl - limb file already exists\n";
      _generate_plot( $yy, $mm, $dd, $hh, $wl, $fn );
      next;
    }
    if ( -z $fn ) {
      print "# Removing empty limb file $fn\n";
      unlink $fn;
    }
    _exec_test_limbfit( $yy, $mm, $dd, $hh, $wl );
  }
  $wl_gaps++;
}

close $patch_fh or warn "Cannot close patch file '$patch_file': $!\n";

if ( $temporal || $wl_gaps ) {
  print "\n# Staged outputs in $cfg->{check_gaps_dir}\n";
  print "#   .limb files  -> $cfg->{check_gaps_dir}/limb/\n";
  print "#   plots        -> $cfg->{check_gaps_dir}/limb/\n"         if $wl_gaps;
  print "#   masterpoint  -> $cfg->{check_gaps_dir}/stage/\n"        if $temporal;
  print "#   patch        -> $patch_file\n"                          if $wl_gaps;
  print "# Commit temporal gaps:\n"                                  if $temporal;
  print "#   update3h_mpt.pl -srcdir=$cfg->{check_gaps_dir}/stage\n" if $temporal;
  print "# Commit wavelength gaps:\n"                                if $wl_gaps;
  print "#   cat $patch_file | update_nans.pl\n"                     if $wl_gaps;
}

if ( $temporal == 0 && $wl_gaps == 0 && $slot_issues == 0 ) {
  print "No gaps detected in $qt\n";
}
elsif ( $temporal || $slot_issues || @backfill_failures ) {
  print "---\n";
  print "Temporal gaps: $temporal\n"   if $temporal;
  print "Backfill slots: $backfills\n" if $backfills;
  print "Backfill failures: ", scalar @backfill_failures, "\n" if @backfill_failures;
  print "Slot issues: $slot_issues\n"  if $slot_issues;
  if (@backfill_failures) {
    print "Failed backfill slots:\n";
    for my $failure (@backfill_failures) {
      printf "  %d-%.2d-%.2d %.2d:00 UTC: %s\n",
        $failure->{year}, $failure->{month}, $failure->{day}, $failure->{hour}, $failure->{reason};
    }
  }
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

sub _is_bridgeable_wrong_duration ( $rec, $issues ) {
  return 0 unless @{$issues} == 1 && $issues->[0] eq 'wrong_duration';
  return 0 unless defined $rec->{start} && defined $rec->{stop};
  my $duration = $rec->{stop} - $rec->{start};
  return $duration > $cadence_s && $duration % $cadence_s == 0;
}

sub _slot_has_limb_files ( $y, $m, $d, $h, $quiet = 0 ) {
  my $dir = sprintf "$cfg->{check_gaps_dir}/limb/%d/%.2d/%.2d", $y, $m, $d;
  return 0 unless -d $dir;

  my @missing;
  for my $wl (@wl) {
    my $f = sprintf "$dir/%d%.2d%.2d_%.2d_%.4d.limb", $y, $m, $d, $h, $wl;
    if ( -e $f && !-s $f ) {
      print "# Removing empty limb file $f\n";
      unlink $f;
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

sub _generate_plot ( $y, $m, $d, $h, $wl, $limb_path ) {    ## no critic (Subroutines::ProhibitManyArgs)
  my $limb =
    defined $limb_path
    ? $limb_path
    : sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
    $fits_root, $y, $m, $d, $y, $m, $d, $h, $wl;
  my $plot = $limb;
  $plot =~ s/[.]limb$/.png/;

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

sub _plot_all_in_range ( $y0, $m0, $d0, $y1, $m1, $d1 ) {    ## no critic (Subroutines::ProhibitManyArgs)
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

sub _write_context_file ( $y, $m, $d, $h, $wl ) {
  my $target_ts = timegm( 0, 0, $h, $d, $m - 1, $y );
  my $start_ts  = $target_ts - 3 * 86_400;
  my $end_ts    = $target_ts + 3 * 86_400;
  my ( $sy, $sm, $sd ) = ( gmtime $start_ts )[ 5, 4, 3 ];
  my ( $ey, $em, $ed ) = ( gmtime $end_ts )[ 5, 4, 3 ];
  $sy += 1900;
  $sm++;
  $ey += 1900;
  $em++;

  my $ctx_key = sprintf 'T_START,A_%.3d_X0,A_%.3d_Y0', $wl, $wl;
  my $cqt     = sprintf '%s[%d.%.2d.%.2d_00:00-%d.%.2d.%.2d_23:59]',
    $series, $sy, $sm, $sd, $ey, $em, $ed;
  my @clines;
  try { @clines = _show_info( '-q', "key=$ctx_key", $cqt ) }
  catch ($e) {
    warn $e;
    return;
  }

  chomp @clines;
  @clines = grep { /\S/ } @clines;
  return if @clines == 0;

  my $ctx_dir = sprintf "$cfg->{check_gaps_dir}/context/%d/%.2d/%.2d", $y, $m, $d;
  make_path( $ctx_dir, { chmod => oct('755') } );
  my $ctx_file = sprintf "$ctx_dir/%d%.2d%.2d_%.2d_%.4d_context.txt", $y, $m, $d, $h, $wl;
  open my $cfh, '>', $ctx_file or do {
    warn "Cannot write context file '$ctx_file': $!\n";
    return;
  };
  for my $line (@clines) {
    print {$cfh} $line, "\n";
  }
  close $cfh or warn "Cannot close context file '$ctx_file': $!\n";
  print "# context  $ctx_file  (", scalar @clines, " records)\n";
  return;
}

sub _exec_limbfit ( $y, $m, $d, $h ) {
  my $limb_dir          = "$cfg->{check_gaps_dir}/limb";
  my $stage_dir         = "$cfg->{check_gaps_dir}/stage";
  my @series_candidates = defined $image_series ? ($image_series) : do {
    my %seen;
    grep { defined $_ && length $_ && !$seen{$_}++ } ( $cfg->{lev1_series}, 'aia.lev1' );
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

  my @red_cmd = (
    $^X,        "$lf2mpr",   "-inpdir=$limb_dir", "-outdir=$stage_dir",
    "-year=$y", "-month=$m", "-day=$d",           "-hour=$h",
  );
  print "# @red_cmd\n";
  return if $dry_run;
  system(@red_cmd) == 0 or die "lf2mpr_nrt.pdl failed for $y-$m-$d $h:00: exit=$?\n";
  print "# Reduced slot using $used_series\n" if defined $used_series;

  for my $wl ( @{ $cfg->{wl} } ) {
    my $limb = sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
      $limb_dir, $y, $m, $d, $y, $m, $d, $h, $wl;
    _generate_plot( $y, $m, $d, $h, $wl, $limb );
    _write_context_file( $y, $m, $d, $h, $wl );
  }
  return;
}

sub _exec_test_limbfit ( $y, $m, $d, $h, $wl ) {
  my $limb_dir = "$cfg->{check_gaps_dir}/limb";
  my @cmd      = (
    $^X,       "$run_test", "-year=$y",   "-month=$m",
    "-day=$d", "-hour=$h",  "-wavel=$wl", "-outroot=$limb_dir",
    '-no-plots',
  );
  push @cmd, "-series=$image_series" if defined $image_series;
  print "# @cmd\n";
  return if $dry_run;
  system(@cmd) == 0 or die "run_limbfit_test.pl failed for $y-$m-$d $h:00 ${wl}A: exit=$?\n";

  my $limb = sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
    $limb_dir, $y, $m, $d, $y, $m, $d, $h, $wl;
  _generate_plot( $y, $m, $d, $h, $wl, $limb );
  _write_context_file( $y, $m, $d, $h, $wl );
  return;
}
