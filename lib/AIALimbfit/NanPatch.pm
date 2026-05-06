package AIALimbfit::NanPatch;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(limb_path patch_commands parse_patch_line);

sub parse_patch_line {
  my ($line) = @_;
  return unless defined $line && $line =~ /\S/;
  my ( $dt, $wavelength, $x_center, $y_center ) = split /\s+/, $line;
  return unless defined $dt && defined $wavelength && $dt =~ /T/;
  my ( $ymd, $hms ) = split /T/, $dt;
  my ( $year, $month, $day ) = split /-/, $ymd;
  return unless defined $year && defined $month && defined $day && defined $hms;
  $hms =~ s/Z$//;
  my ( $hour, $minute, $second ) = split /:/, $hms;
  return unless defined $hour && defined $minute && defined $second;
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

sub limb_path {
  my ( $fits_root, $entry ) = @_;
  return sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%4.4d.limb',
    $fits_root, $entry->{year}, $entry->{month}, $entry->{day}, $entry->{year}, $entry->{month},
    $entry->{day}, $entry->{hour}, $entry->{wavelength};
}

sub patch_commands {
  my ( $entry, %args ) = @_;
  my $path = limb_path( $args{fits_root}, $entry );
  return (
    [ 'sed', '-i', '-f', $args{lf_sed}, $path ],
    [
      $args{perl}, $args{lf2mpr}, '-inpdir', $args{fits_root}, '-outdir', $args{update_dir},
      '-y', $entry->{year}, '-mo', $entry->{month}, '-da', $entry->{day}, '-h', $entry->{hour},
    ],
    [ $args{perl}, $args{update3h}, '-src', $args{update_dir}, '-ser', $args{series} ],
  );
}

1;
