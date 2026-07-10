package AIALimbfit::LimbfitCommand;

use strict;
use warnings;
use Exporter qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(
  dated_dir
  limb_filename
  limb_output_path
  limbfit_command
  limbfit_query
  plot_command
  plot_path
  shell_quote
  validate_limbfit_args
  wavelength_sum
);

sub dated_dir {
  my ( $root, $year, $month, $day ) = @_;
  return sprintf '%s/%d/%.2d/%.2d', $root, $year, $month, $day;
}

sub limb_filename {
  my ( $year, $month, $day, $hour, $wavelength ) = @_;
  return sprintf '%d%.2d%.2d_%.2d_%.4d.limb', $year, $month, $day, $hour, $wavelength;
}

sub limb_output_path {
  my ( $root, $year, $month, $day, $hour, $wavelength ) = @_;
  return dated_dir( $root, $year, $month, $day ) . '/' . limb_filename( $year, $month, $day, $hour, $wavelength );
}

sub limbfit_query {
  my (%args) = @_;
  return sprintf '%s[%d.%.2d.%.2d_%.2d/%s][?WAVELNTH=%d?]%s',
    $args{series}, $args{year}, $args{month}, $args{day}, $args{hour}, $args{duration},
    $args{wavelength}, $args{filter};
}

sub wavelength_sum {
  my ($wavelength) = @_;
  return $wavelength < 1500 ? 5 : $wavelength < 4000 ? 3 : 1;
}

sub validate_limbfit_args {
  my (%args) = @_;
  for my $name (qw(year month day hour)) {
    die "Missing required option: --$name\n" unless defined $args{$name};
  }

  my $valid = eval { timegm( 0, 0, $args{hour}, $args{day}, $args{month} - 1, $args{year} ); 1 };
  die sprintf "Invalid slot date/time: %d-%02d-%02d %02d:00 UTC\n",
    @args{qw(year month day hour)}
    unless $valid;

  if ( defined $args{wavelength} && defined $args{wavelengths} ) {
    die "Unsupported wavelength: $args{wavelength}\n"
      unless grep { $_ == $args{wavelength} } @{ $args{wavelengths} };
  }
  return;
}

sub shell_quote {
  my ($value) = @_;
  $value =~ s/'/'"'"'/g;
  return "'$value'";
}

sub limbfit_command {
  my (%args) = @_;
  return sprintf '%s dsinp=%s sum=%d > %s',
    $args{limbfit_exe}, shell_quote( $args{query} ), $args{sum}, shell_quote( $args{outpath} );
}

sub plot_path {
  my ($limb_path) = @_;
  ( my $plot = $limb_path ) =~ s/[.]limb$/.png/;
  return $plot;
}

sub plot_command {
  my (%args) = @_;
  return ( $args{plotter}, $args{limb_path}, '-o', plot_path( $args{limb_path} ), '--perl', $args{perl} );
}

1;
