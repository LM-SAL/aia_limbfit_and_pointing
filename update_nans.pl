#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::NanPatch qw(limb_path parse_patch_line patch_commands);
use Getopt::Long;

# Re-reduce already regenerated limb files and update aia.master_pointing3h.
# Reads whitespace-separated records from stdin:
#   YYYY-MM-DDTHH:MM:SSZ  wavelength  x_centre  y_centre
#
# Prefer check_pointing_gaps.pl -repair for new repairs.  This compatibility
# entry point accepts the historical input format but does not edit .limb files.
# Example:
#   grep ^2024 aia.master_pointing3h_miss.171 | ./update_nans.pl

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{SUMSERVER} = $cfg->{sumserver};
my $dry_run = 0;

GetOptions( 'dry-run' => \$dry_run );

my $fits_root  = $cfg->{fits_root};
my $update_dir = $cfg->{update_dir};
my $series     = $cfg->{mpt_series};

while (<>) {
  my $entry = parse_patch_line($_);
  next unless $entry;
  my $fn = limb_path( $fits_root, $entry );
  print "$fn\n";
  die "Limb file is missing or empty: $fn\n" if !$dry_run && !-s $fn;
  my @commands = patch_commands(
    $entry,
    fits_root  => $fits_root,
    update_dir => $update_dir,
    series     => $series,
    perl       => $^X,
    lf2mpr     => "$RealBin/lf2mpr_nrt.pdl",
    update3h   => "$RealBin/update3h_mpt.pl",
  );
  if ($dry_run) {
    print join( q{ }, @{$_} ), "\n" for @commands;
    next;
  }
  system( @{ $commands[0] } ) == 0 or die "lf2mpr failed\n";
  system( @{ $commands[1] } ) == 0 or die "update3h failed\n";
}
