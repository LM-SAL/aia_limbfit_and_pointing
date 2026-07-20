package AIALimbfit::DrmsRuntime;

use v5.38;
use Exporter qw(import);

our @EXPORT_OK = qw(validate_drms_runtime show_info_lines);

sub validate_drms_runtime ($show_info) {
  for my $key (qw(DRMS_BINS_INSTALL_DIR DRMS_LIBS_INSTALL_DIR DRMS_INCS_INSTALL_DIR)) {
    die "Environment variable $key is not set\n"       unless $ENV{$key};
    die "Directory $ENV{$key} ($key) does not exist\n" unless -d $ENV{$key};
  }
  die "SUMSERVER is not set\n"                              unless $ENV{SUMSERVER};
  die "show_info not found or not executable: $show_info\n" unless -x $show_info;
  return;
}

sub show_info_lines ( $show_info, @args ) {
  open my $fh, q{-|}, $show_info, @args or die "Cannot run $show_info: $!\n";
  my @lines = <$fh>;
  close $fh or die "show_info failed (@args): exit=$?\n";
  return @lines;
}

1;
