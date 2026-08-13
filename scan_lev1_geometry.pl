#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime qw(configure_drms_environment validate_drms_runtime show_info_lines);
use Getopt::Long;
use Scalar::Util qw(looks_like_number);

sub usage {
  return <<'USAGE';
Usage: scan_lev1_geometry.pl -ds='<DRMS record set>'

Reports Level-1 records whose R_SUN, CRPIX1, or CRPIX2 is NaN, non-numeric,
zero, or negative, or whose CRVAL1 or CRVAL2 is NaN or non-numeric (zero is
the nominal CRVAL). The record set is required so a scan is always bounded.
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
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

my $show_info = $cfg->{show_info};
validate_drms_runtime($show_info);

my @keys  = qw(FSN T_OBS WAVELNTH R_SUN CRPIX1 CRPIX2 CRVAL1 CRVAL2);
my @lines = show_info_lines( $show_info, '-q', q{key=} . join( q{,}, @keys ), $ds );
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
    my $key = $keys[$index];
    my $is_bad =
      $key =~ /\ACRVAL/
      ? !finite_number( $values[$index] )
      : invalid_geometry_value( $values[$index] );
    push @bad, $key if $is_bad;
  }
  next unless @bad;

  $invalid++;
  printf
qq{INVALID FSN=%s T_OBS=%s WAVELNTH=%s R_SUN=%s CRPIX1=%s CRPIX2=%s CRVAL1=%s CRVAL2=%s fields=%s\n},
    @values, join( q{,}, @bad );
}

printf "SUMMARY records=%d invalid=%d\n", $records, $invalid;
exit( $invalid ? 1 : 0 );

sub invalid_geometry_value ($value) {
  return 1 unless finite_number($value);
  return $value <= 0;
}

sub finite_number ($value) {
  return 0 unless defined $value && length $value;
  return 0 if $value =~ /\A[+-]?(?:nan|inf(?:inity)?)\z/i;
  return looks_like_number($value);
}
