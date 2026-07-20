package AIALimbfit::Inventory;

use v5.38;
use Exporter    qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(expected_limb_path missing_limb_paths);

sub expected_limb_path ( $root, $year, $month, $day, $hour, $wavelength ) {
  return sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
    $root, $year, $month, $day, $year, $month, $day, $hour, $wavelength;
}

sub missing_limb_paths (%args) {
  my $root      = $args{fits_root};
  my $cadence_h = $args{cadence_h};
  my $end_epoch = $args{end_epoch} // ( $args{now_epoch} - ( $args{buffer_s} // 87_000 ) );
  my $t         = timegm( 0, 0, 0, $args{day}, $args{month} - 1, $args{year} );

  my @missing;
  while ( $t < $end_epoch ) {
    my ( undef, undef, $hour, $day, $month, $year ) = gmtime $t;
    $year  += 1900;
    $month += 1;
    for my $wavelength ( @{ $args{wavelengths} } ) {
      my $path = expected_limb_path( $root, $year, $month, $day, $hour, $wavelength );
      push @missing, $path unless -s $path;
    }
    $t += $cadence_h * 3600;
  }

  return @missing;
}

1;
