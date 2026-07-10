package AIALimbfit::NanPatch;

use v5.42;
use Exporter qw(import);

our @EXPORT_OK = qw(limb_path patch_commands parse_patch_line);

sub parse_patch_line ($line) {
  return unless defined $line && $line =~ /\S/;
  my $value_re = qr{
    (?: [+-]? (?: \d+ (?: [.] \d* )? | [.] \d+ ) (?: [eE] [+-]? \d+ )? )
    | (?i:nan|missing)
  }x;

  my ( $year, $month, $day, $hour, $minute, $second, $wavelength, $x_center, $y_center ) = $line =~ m{
    ^ \s*
    (\d{4}) - (\d{2}) - (\d{2})
    T
    (\d{2}) : (\d{2}) : (\d{2}) Z
    \s+
    (\d+)
    \s+
    ($value_re)
    \s+
    ($value_re)
    \s* $
  }x;
  return unless defined $y_center;

  my $dt = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ',
    $year, $month, $day, $hour, $minute, $second;
  return {
    datetime   => $dt,
    wavelength => $wavelength + 0,
    x_center   => $x_center,
    y_center   => $y_center,
    year       => $year + 0,
    month      => $month + 0,
    day        => $day + 0,
    hour       => $hour + 0,
    minute     => $minute + 0,
    second     => $second + 0,
  };
}

sub limb_path ( $fits_root, $entry ) {
  return sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%4.4d.limb',
    $fits_root, $entry->{year}, $entry->{month}, $entry->{day}, $entry->{year}, $entry->{month},
    $entry->{day}, $entry->{hour}, $entry->{wavelength};
}

sub patch_commands ( $entry, %args ) {
  return (
    [
      $args{perl}, $args{lf2mpr}, '-inpdir', $args{fits_root}, '-outdir', $args{update_dir},
      '-y', $entry->{year}, '-mo', $entry->{month}, '-da', $entry->{day}, '-h', $entry->{hour},
      '-require-all',
    ],
    [ $args{perl}, $args{update3h}, '-src', $args{update_dir}, '-ser', $args{series} ],
  );
}

1;
