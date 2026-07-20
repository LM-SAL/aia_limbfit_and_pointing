package AIALimbfit::LimbfitCommand;

use v5.38;
use feature 'try';
no warnings 'experimental::try';
use Exporter    qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(
  dated_dir
  limb_filename
  limbfit_argv
  limbfit_command
  limbfit_query
  plot_command
  plot_path
  run_limbfit_to_file
  shell_quote
  validate_limbfit_args
  wavelength_sum
);

sub dated_dir ( $root, $year, $month, $day ) {
  return sprintf '%s/%d/%.2d/%.2d', $root, $year, $month, $day;
}

sub limb_filename ( $year, $month, $day, $hour, $wavelength ) {
  return sprintf '%d%.2d%.2d_%.2d_%.4d.limb', $year, $month, $day, $hour, $wavelength;
}

sub limbfit_query (%args) {
  return sprintf '%s[%d.%.2d.%.2d_%.2d/%s][?WAVELNTH=%d?]%s',
    $args{series}, $args{year}, $args{month}, $args{day}, $args{hour}, $args{duration},
    $args{wavelength}, $args{filter};
}

sub wavelength_sum ($wavelength) {
  return $wavelength < 1500 ? 5 : $wavelength < 4000 ? 3 : 1;
}

sub validate_limbfit_args (%args) {
  for my $name (qw(year month day hour)) {
    die "Missing required option: --$name\n" unless defined $args{$name};
  }

  my $valid = eval { timegm( 0, 0, $args{hour}, $args{day}, $args{month} - 1, $args{year} ); 1 };
  die sprintf "Invalid slot date/time: %d-%02d-%02d %02d:00 UTC\n", @args{qw(year month day hour)}
    unless $valid;

  if ( defined $args{wavelength} && defined $args{wavelengths} ) {
    die "Unsupported wavelength: $args{wavelength}\n"
      unless grep { $_ == $args{wavelength} } @{ $args{wavelengths} };
  }
  return;
}

sub shell_quote ($value) {
  $value =~ s/'/'"'"'/g;
  return "'$value'";
}

sub limbfit_command (%args) {
  return sprintf '%s dsinp=%s sum=%d > %s',
    $args{limbfit_exe}, shell_quote( $args{query} ), $args{sum}, shell_quote( $args{outpath} );
}

sub limbfit_argv (%args) {
  return ( $args{limbfit_exe}, "dsinp=$args{query}", "sum=$args{sum}" );
}

sub run_limbfit_to_file (%args) {

  open my $out_fh, '>', $args{outpath}
    or die "Cannot open '$args{outpath}' for writing: $!\n";

  my @argv = limbfit_argv(%args);

  my $status;
  open my $saved_stdout, '>&', \*STDOUT
    or die "Cannot save STDOUT before writing '$args{outpath}': $!\n";
  open STDOUT, '>&', $out_fh
    or die "Cannot redirect STDOUT to '$args{outpath}': $!\n";
  my $run_error;
  try {
    $status = system { $argv[0] } @argv;
  }
  catch ($e) { $run_error = $e }
  open STDOUT, '>&', $saved_stdout
    or die "Cannot restore STDOUT after writing '$args{outpath}': $!\n";
  die $run_error if defined $run_error;

  close $out_fh
    or die "Cannot close '$args{outpath}': $!\n";

  unlink $args{outpath} if $status != 0 && -e $args{outpath};
  return $status;
}

sub plot_path ($limb_path) {
  ( my $plot = $limb_path ) =~ s/[.]limb$/.png/;
  return $plot;
}

sub plot_command (%args) {
  return ( $args{plotter}, $args{limb_path}, '-o', plot_path( $args{limb_path} ),
    '--perl', $args{perl} );
}

1;
