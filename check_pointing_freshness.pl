#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(configure_drms_environment show_info_lines);
use AIALimbfit::Slot        qw(iso8601 ts2ymdh tstr2ts);
use Getopt::Long;

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

my $series      = $cfg->{mpt_series};
my $grace_hours = 24;
my $gap_days    = 7;
my $now         = time;
GetOptions(
  'series=s'      => \$series,
  'grace-hours=i' => \$grace_hours,
  'gap-days=i'    => \$gap_days,
  'now=i'         => \$now,
) or die "Invalid options\n";
die "-grace-hours must be positive\n" if $grace_hours <= 0;
die "-gap-days must be positive\n"    if $gap_days <= 0;

my $grace_s       = $grace_hours * 3600;
my $cadence_s     = ( $cfg->{cadence_h} // 3 ) * 3600;
my $lookback_days = 30;
my $query         = sprintf '%s[%s-%s]', $series,
  _drms_range_time( $now - $grace_s - $lookback_days * 86_400 ), _drms_range_time($now);
my $now_text = iso8601($now);

my @lines = eval { show_info_lines( $cfg->{show_info}, '-q', 'key=DATE,T_START,T_STOP', $query ) };
if ( my $error = $@ ) {
  _alert( "$series freshness check failed",
    "Cannot query $series, so the table cannot be checked:\n$error" );
}
chomp @lines;
@lines = grep { /\S/ } @lines;

my @records;
my $newest;
for my $line (@lines) {
  my @field = split /\s+/, $line;
  next if @field < 3;
  my $date = tstr2ts( $field[0] );
  next unless defined $date;
  my $pointing = {
    date_epoch => $date,
    date       => $field[0],
    t_start    => $field[1],
    t_stop     => $field[2],
    start      => tstr2ts( $field[1] ),
    stop       => tstr2ts( $field[2] ),
  };
  push @records, $pointing;
  $newest = $pointing if !$newest || $pointing->{date_epoch} > $newest->{date_epoch};
}

if ( !$newest ) {
  my $found =
    @lines
    ? "Records exist, but none carries a readable DATE."
    : "No $series records were found in the last $lookback_days days.";
  _alert(
    "$series update missing",
    "$found\nCannot confirm that the table is being updated.\n\n"
      . "  watchdog time: $now_text\n"
      . "  query:         $query\n\n"
      . _advice()
  );
}

my $age_h = ( $now - $newest->{date_epoch} ) / 3600;
_alert(
  sprintf( '%s update missing for %.0f h',                    $series, $age_h ),
  sprintf( "%s has not been updated for more than %d h.\n\n", $series, $grace_hours )
    . "  watchdog time:      $now_text\n"
    . sprintf( "  newest DATE:        %s (%.1f h ago)\n", $newest->{date}, $age_h )
    . sprintf( "  allowed update age: %d h (latest acceptable was %s)\n",
    $grace_hours, iso8601( $now - $grace_s ) )
    . "  query:              $query\n\n"
    . sprintf( "Newest record: T_START=%s T_STOP=%s DATE=%s\n\n",
    $newest->{t_start}, $newest->{t_stop}, $newest->{date} )
    . _advice()
) if $age_h > $grace_hours;

my $gap_cutoff = $now - $gap_days * 86_400;
my @gaps       = _recent_gaps( \@records, $gap_cutoff, $cadence_s );
if (@gaps) {
  _alert(
    sprintf( '%s coverage gaps: %d',                              $series, scalar @gaps ),
    sprintf( "%s has coverage gaps within the last %d days:\n\n", $series, $gap_days )
      . _gap_lines( \@gaps )
      . "\n  watchdog time: $now_text\n"
      . "  query:         $query\n\n"
      . _gap_advice($gap_cutoff)
  );
}

exit 0;

sub _advice {
  my $logs = $cfg->{logs_dir} // 'the pipeline log directory';
  return
      "The hourly cron that publishes this table may be down. On the JSOC host:\n"
    . "  crontab -l\n"
    . "  tail -n 20 $logs/*.log\n"
    . "Then run $RealBin/check_pointing_gaps.pl to list the missing slots.\n";
}

# Same coverage rule as check_pointing_gaps.pl: a cadence-aligned block is
# covered when the previous T_STOP reaches the later T_START, so provisional
# six-hour records hide single missed slots and only real holes are reported.
sub _recent_gaps ( $records, $cutoff, $cadence_s ) {
  my %coverage;
  for my $pointing ( @{$records} ) {
    next unless defined $pointing->{start} && defined $pointing->{stop};
    my $start = $pointing->{start};
    $coverage{$start} = $pointing->{stop}
      if !exists $coverage{$start} || $pointing->{stop} > $coverage{$start};
  }

  my @starts = sort { $a <=> $b } keys %coverage;
  my @holes;
  my $epsilon = 2;
  for my $i ( 1 .. $#starts ) {
    my ( $previous, $current ) = @starts[ $i - 1, $i ];
    next if $current < $cutoff;

    my $difference = $current - $previous;
    next if $difference < $cadence_s + $epsilon;
    next
      if $difference % $cadence_s <= $epsilon
      && abs( $coverage{$previous} - $current ) <= $epsilon;
    push @holes, { previous => $previous, current => $current };
  }
  return @holes;
}

sub _gap_lines ($gaps) {
  my $text = q{};
  for my $gap ( @{$gaps} ) {
    my $difference = $gap->{current} - $gap->{previous};
    my $missing =
      $difference % $cadence_s
      ? q{}
      : sprintf ', %d missing slots', $difference / $cadence_s - 1;
    $text .= sprintf "  %s -> %s (%.1f h%s)\n", iso8601( $gap->{previous} ),
      iso8601( $gap->{current} ), $difference / 3600, $missing;
  }
  return $text;
}

sub _gap_advice ($cutoff) {
  my ( $year,     $month,     $day )     = ts2ymdh($cutoff);
  my ( $end_year, $end_month, $end_day ) = ts2ymdh($now);
  return
      "Run $RealBin/check_pointing_gaps.pl to inspect the holes and stage refits:\n"
    . "  $RealBin/check_pointing_gaps.pl -year=$year -month=$month -day=$day"
    . " -end_year=$end_year -end_month=$end_month -end_day=$end_day\n";
}

sub _alert ( $subject, $body ) {
  my @recipients = grep { length } split /,/, ( $cfg->{mail_to} // q{} );
  if (@recipients) {
    if ( open my $mail_fh, q{|-}, q{mailx}, '-s', $subject, @recipients ) {
      print {$mail_fh} $body;
      close $mail_fh or warn "mailx failed: $?\n";
    }
    else {
      warn "cannot start mailx: $!\n";
    }
  }
  $body .= "\n" unless $body =~ /\n\z/;
  die $body;
}

sub _drms_range_time ($ts) {
  my ( undef, $min, $hour, $mday, $mon, $year ) = gmtime $ts;
  return sprintf '%d.%.2d.%.2d_%.2d:%.2d', $year + 1900, $mon + 1, $mday, $hour, $min;
}
