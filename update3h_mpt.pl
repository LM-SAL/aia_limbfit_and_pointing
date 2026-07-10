#!/home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin        qw($RealBin);
use File::Basename qw(dirname);
use lib "$RealBin/lib";
use AIALimbfit::Slot
  qw(iso8601 series_contains_time_query slot_bounds_from_masterpoint slot_record_issues);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{TZ} = $cfg->{tz};
$ENV{SUMSERVER} //= $cfg->{sumserver};
my $drms_bin_dir = dirname( $cfg->{show_info} );
my $drms_base    = dirname( dirname($drms_bin_dir) );
$ENV{DRMS_ROOT_DIR}           //= $drms_base;
$ENV{DRMS_INSTALL_DIR}        //= $drms_base;
$ENV{DRMS_BINS_INSTALL_DIR}   //= $drms_bin_dir;
$ENV{DRMS_LIBS_INSTALL_DIR}   //= "$drms_base/lib/linux_avx2";
$ENV{DRMS_INCS_INSTALL_DIR}   //= "$drms_base/include";
$ENV{DRMS_PARAMS_INSTALL_DIR} //= "$drms_base/include/base";
$ENV{DRMS_SCRS_INSTALL_DIR}   //= "$drms_base/scripts";
$ENV{DRMS_SRC_INSTALL_DIR}    //= "$drms_base/src";

my $mpre      = '^masterpoint_20';
my $del       = 0;
my $dry_run   = 0;
my $series    = $cfg->{mpt_series};
my $sdo       = $cfg->{sdo_series};
my $src       = $cfg->{pointing_dir};
my $set_info  = $cfg->{set_info};
my $show_info = $cfg->{show_info};

sub _show_info {
  my (@args) = @_;
  open my $fh, q{-|}, $show_info, @args or die "Cannot run $show_info: $!\n";
  my @lines = <$fh>;
  close $fh or die "show_info failed (@args): exit=$?\n";
  return @lines;
}

for my $key (qw(DRMS_BINS_INSTALL_DIR DRMS_LIBS_INSTALL_DIR DRMS_INCS_INSTALL_DIR)) {
  die "Environment variable $key is not set\n"       unless $ENV{$key};
  die "Directory $ENV{$key} ($key) does not exist\n" unless -d $ENV{$key};
}
die "SUMSERVER is not set\n"                              unless $ENV{SUMSERVER};
die "show_info not found or not executable: $show_info\n" unless -x $show_info;
die "set_info not found or not executable: $set_info\n"   unless -x $set_info;

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
  my @slot_issues = slot_record_issues( $slot, cadence_s => ( $cfg->{cadence_h} // 3 ) * 3600 );
  if (@slot_issues) {
    warn "Skipping $mpu: invalid slot (" . join( ', ', @slot_issues ) . ")\n";
    next;
  }
  my $trec  = $slot->{t_start};
  my $tstop = $slot->{t_stop};
  my $fmtim = ( stat("$src/$mpu") )[9];

  my $qs    = series_contains_time_query( $sdo, $trec );
  my @lines = _show_info( '-a', $qs );
  next if @lines <= 1;

  chomp( my @keys = split /\t/, $lines[0] );
  chomp( my @vals = split /\t/, $lines[1] );
  my %kvsdo;
  @kvsdo{@keys} = @vals;

  $kvsdo{T_STOP}  = $tstop;
  $kvsdo{VERSION} = 1;

  my %mpkv;
  open my $fh, '<', "$src/$mpu" or die "Can't open '$src/$mpu': $!\n";
  while (<$fh>) {
    my @pd = split;
    $mpkv{ $pd[1] } = $pd[2] if /^KWD/;
  }
  close $fh or die "Can't close '$src/$mpu': $!\n";
  die "No KWD values in '$src/$mpu'\n" unless %mpkv;
  @kvsdo{ keys %mpkv } = values %mpkv;

  $qs    = series_contains_time_query( $series, $trec );
  @lines = _show_info( '-a', $qs );

  if ( @lines > 1 ) {
    chomp( my @k = split /\t/, $lines[0] );
    chomp( my @v = split /\t/, $lines[1] );
    my %kv;
    @kv{@k} = @v;
    next
      if $kv{DATE} gt $trec
      && $kv{DATE} gt iso8601($fmtim);

    if ( $kv{VERSION} ) {
      $kvsdo{VERSION} = $kv{VERSION} + 1;
    }
    else {
      my $d       = iso8601();
      my @updates = ( 'DATE=' . $d, 'T_STOP=' . $kvsdo{T_STOP}, 'VERSION=1' );
      push @updates, map { "$_=$mpkv{$_}" } sort keys %mpkv;
      if ($dry_run) {
        print "$set_info ", sprintf( 'ds=%s[%s]', $series, $kv{T_START} ), ' ',
          join( ' ', @updates ), "\n";
      }
      else {
        system( $set_info, sprintf( 'ds=%s[%s]', $series, $kv{T_START} ), @updates, ) == 0
          or warn "set_info update failed for $kv{T_START}: exit=$?\n";
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
    my @cmd = ( $set_info, '-c', "ds=$series" );
    while ( my ( $k, $v ) = each %kvsdo ) {
      push @cmd, "$k=$v";
    }
    system(@cmd) == 0 or die "set_info failed for $trec\n";
  }

  unlink "$src/$mpu" if $del;
}
