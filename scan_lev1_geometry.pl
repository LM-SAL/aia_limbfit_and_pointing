#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(validate_drms_runtime show_info_lines);
use File::Basename qw(dirname);
use Getopt::Long;
use Scalar::Util qw(looks_like_number);

sub usage {
  return <<'USAGE';
Usage: scan_lev1_geometry.pl -ds='<DRMS record set>'

Reports Level-1 records whose R_SUN, CRPIX1, or CRPIX2 is NaN, non-numeric,
zero, or negative. The record set is required so a scan is always bounded.
USAGE
}

my ( $ds, $help );
GetOptions(
  'ds=s'   => \$ds,
  'help|h' => \$help,
) or die usage();

if ($help) {
  print usage();
  exit 0;
}
die usage() unless defined $ds && length $ds;

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
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
validate_drms_runtime($show_info);

my @keys  = qw(FSN T_OBS WAVELNTH R_SUN CRPIX1 CRPIX2);
my @lines = show_info_lines( $show_info, '-q', 'key=' . join( ',', @keys ), $ds );
chomp @lines;
@lines = grep { /\S/ } @lines;

my ( $records, $invalid ) = ( 0, 0 );
for my $line (@lines) {
  my @values = split /\s+/, $line;
  die "Expected " . scalar(@keys) . " fields from show_info, got: $line\n"
    unless @values == @keys;
  $records++;

  my @bad;
  for my $index ( 3 .. $#keys ) {
    push @bad, $keys[$index] if invalid_geometry_value( $values[$index] );
  }
  next unless @bad;

  $invalid++;
  printf "INVALID FSN=%s T_OBS=%s WAVELNTH=%s R_SUN=%s CRPIX1=%s CRPIX2=%s fields=%s\n",
    @values, join( ',', @bad );
}

printf "SUMMARY records=%d invalid=%d\n", $records, $invalid;
exit( $invalid ? 1 : 0 );

sub invalid_geometry_value ($value) {
  return 1 unless defined $value && length $value;
  return 1 if $value =~ /\A[+-]?(?:nan|inf(?:inity)?)\z/i;
  return 1 unless looks_like_number($value);
  return $value <= 0;
}
