package AIALimbfit::Slot;

use v5.42;
use Exporter qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(
  drms_time
  iso8601
  parse_masterpoint_filename
  series_contains_time_query
  slot_bounds_from_masterpoint
  slot_record_issues
  slot_sequence_issues
  tstr2ts
  ts2ymdh
);

sub iso8601 ( $ts = time ) {
  my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime($ts);
  return sprintf '%d-%.2d-%.2dT%.2d:%.2d:%.2dZ', $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
}

sub tstr2ts ($tstr) {
  return unless defined $tstr;
  my ( $ymd, $hms ) = split /T/, $tstr;
  return unless defined $ymd && defined $hms;
  my ( $yr, $mo, $da ) = split /-/, $ymd;
  my ( $hr, $mn, $sc ) = split /:/, $hms;
  return unless defined $yr && defined $mo && defined $da && defined $hr && defined $mn && defined $sc;
  $sc =~ s/Z$//;
  my $ts;
  try { $ts = timegm( $sc, $mn, $hr, $da, $mo - 1, $yr ) }
  catch ($e) { return undef }
  return $ts;
}

sub ts2ymdh ($ts) {
  my ( undef, undef, $h, $d, $m, $y ) = gmtime $ts;
  return ( $y + 1900, $m + 1, $d, $h );
}

sub drms_time ($trec) {
  return sprintf '%c(%s)', 36, $trec;
}

sub parse_masterpoint_filename ($name) {
  return unless defined $name;
  ( my $base = $name ) =~ s{.*/}{};
  my ( $yr, $mo, $da, $hr, $mn, $dur ) =
    $base =~ /^masterpoint_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})_(\d+)hcadence[.]txt$/;
  return unless defined $dur;
  return {
    year       => $yr + 0,
    month      => $mo + 0,
    day        => $da + 0,
    hour       => $hr + 0,
    minute     => $mn + 0,
    duration_h => $dur + 0,
  };
}

sub slot_bounds_from_masterpoint ($source) {
  my $parts = ref $source eq 'HASH' ? { %{$source} } : parse_masterpoint_filename($source);
  return unless $parts;

  my $center_epoch;
  try {
    $center_epoch = timegm( 0, $parts->{minute}, $parts->{hour}, $parts->{day}, $parts->{month} - 1, $parts->{year} );
  }
  catch ($e) { return }

  my $duration_s  = $parts->{duration_h} * 3600;
  my $start_epoch = $center_epoch - int( $parts->{duration_h} * 1800 );
  my $stop_epoch  = $start_epoch + $duration_s;

  return {
    %{$parts},
    center_epoch => $center_epoch,
    start_epoch  => $start_epoch,
    stop_epoch   => $stop_epoch,
    t_start      => iso8601($start_epoch),
    t_stop       => iso8601($stop_epoch),
  };
}

sub series_contains_time_query ( $series, $trec ) {
  my $drms_trec = drms_time($trec);
  return sprintf '%s[?T_START<=%s and %s<T_STOP?]', $series, $drms_trec, $drms_trec;
}

sub _record_epoch ( $rec, $epoch_key, $time_key ) {
  return $rec->{$epoch_key} // tstr2ts( $rec->{$time_key} );
}

sub _is_on_grid ( $ts, $grid_h ) {
  my ( $sec, $min, $hour ) = gmtime $ts;
  return $sec == 0 && $min == 0 && $hour % $grid_h == 0;
}

sub slot_record_issues ( $rec, %opts ) {
  my $cadence_s = $opts{cadence_s} // 10_800;
  my $grid_h    = $opts{grid_h}    // int( $cadence_s / 3600 );
  $grid_h = 1 if $grid_h < 1;

  my $start = _record_epoch( $rec, 'start', 't_start' );
  my $stop  = _record_epoch( $rec, 'stop',  't_stop' );
  return ('missing_time') unless defined $start && defined $stop;

  my @issues;
  my $duration = $stop - $start;
  if ( $duration <= 0 ) {
    push @issues, 'non_positive_duration';
  }
  elsif ( $duration != $cadence_s ) {
    push @issues, 'wrong_duration';
  }
  push @issues, 'off_grid_start' unless _is_on_grid( $start, $grid_h );
  push @issues, 'off_grid_stop'  unless _is_on_grid( $stop,  $grid_h );
  return @issues;
}

sub slot_sequence_issues ( $records, %opts ) {
  my $epsilon = $opts{epsilon} // 2;

  my @issues;
  for my $rec ( @{$records} ) {
    my @record_issues = slot_record_issues( $rec, %opts );
    push @issues, { type => 'invalid_record', record => $rec, issues => \@record_issues } if @record_issues;
  }

  my @sorted =
    sort { _record_epoch( $a, 'start', 't_start' ) <=> _record_epoch( $b, 'start', 't_start' ) }
    grep { defined _record_epoch( $_, 'start', 't_start' ) && defined _record_epoch( $_, 'stop', 't_stop' ) }
    @{$records};

  for my $i ( 1 .. $#sorted ) {
    my $prev = $sorted[ $i - 1 ];
    my $cur  = $sorted[$i];
    my $diff = _record_epoch( $cur, 'start', 't_start' ) - _record_epoch( $prev, 'stop', 't_stop' );
    if ( $diff > $epsilon ) {
      push @issues, { type => 'gap', prev => $prev, cur => $cur, seconds => $diff };
    }
    elsif ( $diff < -$epsilon ) {
      push @issues, { type => 'overlap', prev => $prev, cur => $cur, seconds => -$diff };
    }
  }

  return @issues;
}

1;
