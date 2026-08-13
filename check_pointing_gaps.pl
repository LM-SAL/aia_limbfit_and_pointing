#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(configure_drms_environment validate_drms_runtime show_info_lines);
use AIALimbfit::Inventory   qw(limb_path);
use AIALimbfit::Reducer     qw(reduce_limb_points);
use AIALimbfit::Slot        qw(tstr2ts ts2ymdh);
use Getopt::Long;
use PDL::IO::Misc;
use Scalar::Util qw(looks_like_number);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

my $series       = $cfg->{mpt_series};
my $image_series = undef;
my $cadence_s    = ( $cfg->{cadence_h} // 3 ) * 3600;
my @wl           = @{ $cfg->{wl} };
my ( $yr, $mo, $da, $eyr, $emo, $eda );
my ( $start_explicit, $end_explicit ) = ( 0, 0 );

GetOptions(
  'year=i'         => sub { $yr  = $_[1]; $start_explicit = 1 },
  'month=i'        => sub { $mo  = $_[1]; $start_explicit = 1 },
  'day=i'          => sub { $da  = $_[1]; $start_explicit = 1 },
  'end_year=i'     => sub { $eyr = $_[1]; $end_explicit   = 1 },
  'end_month=i'    => sub { $emo = $_[1]; $end_explicit   = 1 },
  'end_day=i'      => sub { $eda = $_[1]; $end_explicit   = 1 },
  'series=s'       => \$series,
  'image-series=s' => \$image_series,
) or die "Invalid options\n";

my ( undef, undef, undef, undef, $today_m, $today_y ) = gmtime time;
$today_y += 1900;
$today_m++;
if ($start_explicit) {
  $yr //= $today_y;
  $mo //= 1;
  $da //= 1;
}
else {
  ( $yr, $mo, $da ) = ( 2010, 11, 1 );
}
if ($end_explicit) {
  $eyr //= $today_y;
  $emo //= 12;
  $eda //= 31;
}
elsif ($start_explicit) {
  ( $eyr, $emo, $eda ) = ( $yr, $mo, $da );
}
else {
  my ( undef, undef, undef, $end_d, $end_m, $end_y ) = gmtime( time - 7 * 86_400 );
  ( $eyr, $emo, $eda ) = ( $end_y + 1900, $end_m + 1, $end_d );
}

validate_drms_runtime( $cfg->{show_info} );
my @keys = qw(T_START T_STOP);
for my $w (@wl) {
  push @keys, sprintf 'A_%.3d_X0', $w;
  push @keys, sprintf 'A_%.3d_Y0', $w;
}
my $query = sprintf '%s[%d.%.2d.%.2d_00:00-%d.%.2d.%.2d_23:59]',
  $series, $yr, $mo, $da, $eyr, $emo, $eda;
my @lines = show_info_lines( $cfg->{show_info}, '-q', 'key=' . join( q{,}, @keys ), $query );
chomp @lines;
@lines = grep { /\S/ } @lines;
die "No records found for $query\n" unless @lines;

my @records;
for my $line (@lines) {
  my ( $t_start, $t_stop, @values ) = split /\s+/, $line;
  my ( $start, $stop ) = ( tstr2ts($t_start), tstr2ts($t_stop) );
  next unless defined $start && defined $stop;
  my @missing;
  for my $i ( 0 .. $#wl ) {
    push @missing, $wl[$i]
      if _bad_value( $values[ $i * 2 ],     $cfg->{nan_sentinel} )
      || _bad_value( $values[ $i * 2 + 1 ], $cfg->{nan_sentinel} );
  }
  push @records, { start => $start, stop => $stop, t_start => $t_start, missing => \@missing };
}
@records = sort { $a->{start} <=> $b->{start} } @records;

my ( $temporal, $wavelength_gaps ) = ( 0, 0 );
my %backfill;
my $epsilon = 2;
for my $i ( 1 .. $#records ) {
  my ( $previous, $current ) = @records[ $i - 1, $i ];
  my $difference        = $current->{start} - $previous->{start};
  my $previous_duration = $previous->{stop} - $previous->{start};
  next if $difference < $cadence_s + $epsilon;
  next
    if abs( $difference - 2 * $cadence_s ) <= $epsilon
    && abs( $previous_duration - 2 * $cadence_s ) <= $epsilon;

  printf "TEMPORAL GAP  %s -> %s (%.2f h)\n",
    $previous->{t_start}, $current->{t_start}, $difference / 3600;
  $temporal++;
  if ( $difference % $cadence_s <= $epsilon ) {
    my $first_missing = $previous->{start} + $cadence_s;
    $first_missing += $cadence_s
      if abs( $previous_duration - 2 * $cadence_s ) <= $epsilon;
    for ( my $slot = $first_missing ; $slot < $current->{start} ; $slot += $cadence_s ) {
      $backfill{$slot}{temporal}      = 1;
      $backfill{$slot}{interpolation} = [ $previous->{t_start}, $current->{t_start} ];
    }
  }
  else {
    print "  DIAGNOSIS irregular cadence; inspect T_START/T_STOP manually\n";
  }
}

for my $i ( 0 .. $#records ) {
  my $pointing = $records[$i];
  next unless @{ $pointing->{missing} };
  $wavelength_gaps++;
  print "MISSING WAVELENGTHS  $pointing->{t_start}: ", join( ', ', @{ $pointing->{missing} } ),
    "\n";
  $backfill{ $pointing->{start} }{wavelengths}{$_} = 1 for @{ $pointing->{missing} };
  $backfill{ $pointing->{start} }{interpolation} =
    [ $records[ $i - 1 ]{t_start}, $records[ $i + 1 ]{t_start} ]
    if $i > 0 && $i < $#records;
  for my $w ( @{ $pointing->{missing} } ) {
    my ( $year, $month, $day, $hour ) = ts2ymdh( $pointing->{start} );
    my $path = limb_path( $cfg->{fits_root}, $year, $month, $day, $hour, $w );
    if ( !-s $path ) {
      print "  LIMB $w A: missing or empty $path\n";
      next;
    }

    my ( $xavg, $yavg );
    my $reduced = eval {
      my ( $x, $y ) = rcols $path, 0, 1;
      ( undef, undef, $xavg, $yavg ) = reduce_limb_points( $x, $y, $w, $cfg );
      1;
    };
    my $failure = $@;
    $failure = "non-finite reducer result\n"
      if $reduced && ( "$xavg" =~ /(?:nan|inf)/i || "$yavg" =~ /(?:nan|inf)/i );
    if ( !$reduced || $failure ) {
      $failure =~ s/\s+/ /g;
      $failure =~ s/^ | $//g;
      print "  LIMB $w A: reducer failed: $failure\n";
      if ( $failure =~ /split after row (\d+), segments (\d+)\/(\d+)/ ) {
        $backfill{ $pointing->{start} }{splits}{$w} = [ $1, $2, $3 ];
      }
    }
    else {
      printf "  LIMB %d A: usable (%.3f, %.3f); republish this slot\n", $w, $xavg, $yavg;
      $backfill{ $pointing->{start} }{usable}{$w} = 1;
    }
  }
}

if ( !$temporal && !$wavelength_gaps ) {
  print "No gaps detected in $query\n";
  exit 0;
}

print "---\nTemporal gaps: $temporal\nWavelength gaps: $wavelength_gaps\n";
print "Backfill slots: ", scalar keys %backfill, "\n" if %backfill;
_print_backfill_commands( \%backfill );

sub _bad_value ( $value, $sentinel ) {
  return 1 unless defined $value && length $value;
  return 1 if $value =~ /^(?i:nan|missing)$/;
  return 1 if defined $sentinel && $value eq $sentinel;
  return
       defined $sentinel
    && looks_like_number($value)
    && looks_like_number($sentinel)
    && 0 + $value == 0 + $sentinel;
}

sub _print_backfill_commands ($slots) {
  return unless %{$slots};
  my $perl      = $cfg->{perl_bin} // $^X;
  my $nrt_start = $cfg->{lev1_nrt2_start} ? tstr2ts( $cfg->{lev1_nrt2_start} ) : undef;
  print "\n# Commands only; nothing above changed files or DRMS.\n";
  for my $epoch ( sort { $a <=> $b } keys %{$slots} ) {
    my ( $year, $month, $day, $hour ) = ts2ymdh($epoch);
    my $name   = sprintf '%04d%02d%02d_%02d', $year, $month, $day, $hour;
    my $root   = "$cfg->{check_gaps_dir}/$name";
    my $source = $image_series
      // ( defined $nrt_start && $epoch < $nrt_start ? 'aia.lev1' : $cfg->{lev1_series} );
    print "\n# $year-$month-$day $hour:00 UTC\n";
    my @missing = sort { $a <=> $b } keys %{ $slots->{$epoch}{wavelengths} // {} };
    my $partial =
        !$slots->{$epoch}{temporal}
      && @missing
      && @missing == keys %{ $slots->{$epoch}{usable} // {} };
    if ($partial) {
      print "$perl $RealBin/lf2mpr_nrt.pdl -year=$year -month=$month -day=$day -hour=$hour",
        " -inpdir=$cfg->{fits_root} -outdir=$root/stage",
        map( { " -wavel=$_" } @missing ), "\n";
    }
    else {
      print "$perl $RealBin/run_limbfit_ymdh.pl -year=$year -month=$month -day=$day -hour=$hour",
        " -series=$source -outroot=$root/limb\n";
      for my $w ( sort { $a <=> $b } keys %{ $slots->{$epoch}{splits} // {} } ) {
        my ( $row, $first_segment, $second_segment ) = @{ $slots->{$epoch}{splits}{$w} };
        my $path = limb_path( "$root/limb", $year, $month, $day, $hour, $w );
        print "$RealBin/plot_limb.py $path\n";
        print
"# Choose the physical segment ($first_segment or $second_segment rows), then run ONE of:\n";
        print "head -n $row $path > $path.keep && mv $path.keep $path\n";
        print 'tail -n +', $row + 1, " $path > $path.keep && mv $path.keep $path\n";
      }
      print "$perl $RealBin/lf2mpr_nrt.pdl -year=$year -month=$month -day=$day -hour=$hour",
        " -inpdir=$root/limb -outdir=$root/stage\n";
    }
    if ( my $bounds = $slots->{$epoch}{interpolation} ) {
      print "# Fallback if the regenerated limb fit is physically bad:\n";
      print "$perl $RealBin/lf2mpr_nrt.pdl -year=$year -month=$month -day=$day -hour=$hour",
        " -outdir=$root/stage -interpolate-previous=$bounds->[0] -interpolate-next=$bounds->[1]\n";
    }
    else {
      print "# No interpolation fallback: both bracketing pointing records are required.\n";
    }
    print "$perl $RealBin/update3h_mpt.pl -srcdir=$root/stage -dry-run\n";
  }
  return;
}
