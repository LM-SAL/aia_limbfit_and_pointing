#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use Getopt::Long;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(configure_drms_environment validate_drms_runtime show_info_lines);
use AIALimbfit::Slot
  qw(iso8601 series_contains_time_query slot_bounds_from_masterpoint slot_record_issues tstr2ts);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

my $mpre      = '^masterpoint_20';
my $del       = 0;
my $dry_run   = 0;
my $series    = $cfg->{mpt_series};
my $sdo       = $cfg->{sdo_series};
my $src       = $cfg->{pointing_dir};
my $set_info  = $cfg->{set_info};
my $show_info = $cfg->{show_info};

sub _exact_record ( $show_info, $series, $trec ) {
  my @lines = show_info_lines( $show_info, '-a', sprintf( '%s[%s]', $series, $trec ) );
  return if @lines <= 1;

  chomp @lines;
  my %kv;
  @kv{ split /\t/, $lines[0] } = split /\t/, $lines[1];
  return \%kv;
}

sub _finalize_predecessor ( $show_info, $set_info, $series, $trec, $cadence_s, $dry_run ) {
  my $previous_trec = iso8601( tstr2ts($trec) - $cadence_s );
  my $previous      = _exact_record( $show_info, $series, $previous_trec );
  return 1 unless $previous;
  return 1 if defined $previous->{T_STOP} && $previous->{T_STOP} eq $trec;

  my $date    = iso8601();
  my $version = $previous->{VERSION} // 0;
  my @cmd;
  if ($version) {
    my %replacement = %{$previous};
    @replacement{qw(DATE T_STOP VERSION)} = ( $date, $trec, $version + 1 );
    @cmd = ( $set_info, '-c', "ds=$series", map { "$_=$replacement{$_}" } sort keys %replacement );
  }
  else {
    @cmd = (
      $set_info,    sprintf( 'ds=%s[%s]', $series, $previous_trec ),
      "DATE=$date", "T_STOP=$trec", 'VERSION=1',
    );
  }

  if ($dry_run) {
    print join( q{ }, @cmd ), "\n";
    return 1;
  }

  return 1 if system(@cmd) == 0;
  warn "set_info predecessor update failed for $previous_trec: exit=$?\n";
  return 0;
}

validate_drms_runtime($show_info);
die "set_info not found or not executable: $set_info\n" unless -x $set_info;

GetOptions(
  'delete'   => \$del,
  'dry-run'  => \$dry_run,
  'series=s' => \$series,
  'srcdir=s' => \$src,
);

opendir my $dh, $src or die "Can't open directory '$src': $!\n";
my @files = sort grep { /$mpre/ } readdir $dh;
closedir $dh;

## no critic (RegularExpressions::ProhibitComplexRegexes)
my $masterpoint_re = qr{
  masterpoint_
  (\d{4}) (\d{2}) (\d{2}) _
  (\d{2}) (\d{2}) _
  (\d+) hcadence
}x;

while ( my $mpu = shift @files ) {
  next unless $mpu =~ $masterpoint_re;
  my $slot        = slot_bounds_from_masterpoint($mpu) or next;
  my $cadence_h   = $cfg->{cadence_h} // 3;
  my $cadence_s   = $cadence_h * 3600;
  my @slot_issues = slot_record_issues( $slot, cadence_s => $cadence_s );
  if (@slot_issues) {
    warn "Skipping $mpu: invalid slot (" . join( ', ', @slot_issues ) . ")\n";
    next;
  }
  my $trec  = $slot->{t_start};
  my $fmtim = ( stat("$src/$mpu") )[9];

  my $qs    = series_contains_time_query( $sdo, $trec );
  my @lines = show_info_lines( $show_info, '-a', $qs );
  next if @lines <= 1;

  chomp @lines;
  my %kvsdo;
  @kvsdo{ split /\t/, $lines[0] } = split /\t/, $lines[1];

  $kvsdo{VERSION} = 1;

  my %mpkv;
  open my $fh, '<', "$src/$mpu" or die "Can't open '$src/$mpu': $!\n";
  while (<$fh>) {
    next unless /^KWD\s+(\S+)\s+(\S+)/;
    $mpkv{$1} = $2;
  }
  close $fh or die "Can't close '$src/$mpu': $!\n";
  die "No KWD values in '$src/$mpu'\n" unless %mpkv;

  my $kv = _exact_record( $show_info, $series, $trec );
  for my $w ( @{ $cfg->{wl} // [] } ) {
    my ( $x, $y ) = map { exists $mpkv{ sprintf 'A_%.3d_%s0', $w, $_ } } qw(X Y);
    die "Partial masterpoint '$mpu' has only one coordinate for ${w}A\n" if $x != $y;
  }
  my $partial = $cfg->{wl}
    && grep { !exists $mpkv{ sprintf 'A_%.3d_X0', $_ } || !exists $mpkv{ sprintf 'A_%.3d_Y0', $_ } }
    @{ $cfg->{wl} };
  if ($partial) {
    die "Partial masterpoint '$mpu' requires an existing record at $trec\n" unless $kv;
    %kvsdo = ( %kvsdo, %{$kv} );
  }
  @kvsdo{ keys %mpkv } = values %mpkv;

  # Age guard: skip if the existing DRMS record is newer than the masterpoint file on disk.
  next if $kv && $kv->{DATE} gt iso8601($fmtim);

  my $successor_trec = iso8601( tstr2ts($trec) + $cadence_s );
  my $successor      = _exact_record( $show_info, $series, $successor_trec );
  $kvsdo{T_STOP} = $successor ? $slot->{t_stop} : iso8601( $slot->{stop_epoch} + $cadence_s );

  if ($kv) {
    if ( $kv->{VERSION} ) {
      $kvsdo{VERSION} = $kv->{VERSION} + 1;
    }
    else {
      my $d       = iso8601();
      my @updates = ( 'DATE=' . $d, 'T_STOP=' . $kvsdo{T_STOP}, 'VERSION=1' );
      push @updates, map { "$_=$mpkv{$_}" } sort keys %mpkv;
      my $target_ok;
      if ($dry_run) {
        print "$set_info ", sprintf( 'ds=%s[%s]', $series, $kv->{T_START} ), ' ',
          join( ' ', @updates ), "\n";
        $target_ok = 1;
      }
      else {
        $target_ok =
          system( $set_info, sprintf( 'ds=%s[%s]', $series, $kv->{T_START} ), @updates, ) == 0;
        warn "set_info update failed for $kv->{T_START}: exit=$?\n" unless $target_ok;
      }
      if ($target_ok) {
        my $finalized =
          _finalize_predecessor( $show_info, $set_info, $series, $trec, $cadence_s, $dry_run );
        unlink "$src/$mpu" if $del && !$dry_run && $finalized;
      }
      next;
    }
  }

  $kvsdo{T_START} = $trec;
  $kvsdo{DATE}    = iso8601();

  if ($dry_run) {
    print "$set_info -c ds=$series";
    for my $k ( sort keys %kvsdo ) {
      print " $k=$kvsdo{$k}";
    }
    print "\n";
  }
  else {
    my @cmd = ( $set_info, '-c', "ds=$series", map { "$_=$kvsdo{$_}" } sort keys %kvsdo );
    system(@cmd) == 0 or die "set_info failed for $trec\n";
  }

  my $finalized =
    _finalize_predecessor( $show_info, $set_info, $series, $trec, $cadence_s, $dry_run );
  unlink "$src/$mpu" if $del && !$dry_run && $finalized;
}
