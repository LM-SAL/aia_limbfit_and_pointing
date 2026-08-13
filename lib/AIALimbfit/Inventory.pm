package AIALimbfit::Inventory;

use v5.38;
use Exporter qw(import);

our @EXPORT_OK = qw(limb_path);

sub limb_path ( $root, $year, $month, $day, $hour, $wavelength ) {
  return sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
    $root, $year, $month, $day, $year, $month, $day, $hour, $wavelength;
}

1;
