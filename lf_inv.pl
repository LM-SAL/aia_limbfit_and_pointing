#!/home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::Inventory qw(missing_limb_paths);
use Getopt::Long;

# Gap inventory: scan every expected .limb file from a start date to ~now
# and print any that are absent.  Useful for detecting cron failures and
# identifying intervals that need a back-fill run.
#
# Usage:
#   ./lf_inv.pl                          # scan from 2017-01-01
#   ./lf_inv.pl -year=2024 -month=3      # scan from 2024-03-01
#   ./lf_inv.pl -fits_root=/other/path

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{TZ} = $cfg->{tz};
umask 0002;

my @wl        = @{ $cfg->{wl} };
my $cadence   = $cfg->{cadence_h};
my $fits_root = $cfg->{fits_root};
my ( $yr, $mo, $da ) = ( 2017, 1, 1 );

GetOptions(
  'fits_root=s' => \$fits_root,
  'year=i'      => \$yr,
  'month=i'     => \$mo,
  'day=i'       => \$da,
);

for my $fnam (
  missing_limb_paths(
    fits_root   => $fits_root,
    wavelengths => \@wl,
    cadence_h   => $cadence,
    year        => $yr,
    month       => $mo,
    day         => $da,
    now_epoch   => time,
  )
  )
{
  print "$fnam missing\n";
}
