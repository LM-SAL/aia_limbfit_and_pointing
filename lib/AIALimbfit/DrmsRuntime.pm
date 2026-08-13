package AIALimbfit::DrmsRuntime;

use v5.38;
use Exporter qw(import);
use File::Basename qw(dirname);

our @EXPORT_OK = qw(configure_drms_environment validate_drms_runtime show_info_lines);

sub configure_drms_environment ($cfg) {
  my $root = $cfg->{drms_root_dir};
  my $bins = $cfg->{show_info} ? dirname( $cfg->{show_info} ) : undef;
  $root //= dirname( dirname($bins) ) if defined $bins;
  $bins //= "$root/bin/linux_avx2" if defined $root;
  my %value = (
    TZ                      => $cfg->{tz},
    SUMSERVER               => $cfg->{sumserver},
    SGE_ROOT                => $cfg->{sge_root},
    DRMS_ROOT_DIR           => $root,
    DRMS_INSTALL_DIR        => $root,
    DRMS_BINS_INSTALL_DIR   => $bins,
    DRMS_LIBS_INSTALL_DIR   => defined $root ? "$root/lib/linux_avx2" : undef,
    DRMS_INCS_INSTALL_DIR   => defined $root ? "$root/include"       : undef,
    DRMS_PARAMS_INSTALL_DIR => $cfg->{drms_params_install_dir}
      // ( defined $root ? "$root/include/base" : undef ),
    DRMS_SCRS_INSTALL_DIR => $cfg->{drms_scrs_install_dir}
      // ( defined $root ? "$root/scripts" : undef ),
    DRMS_SRC_INSTALL_DIR => $cfg->{drms_src_install_dir}
      // ( defined $root ? "$root/src" : undef ),
  );
  $ENV{$_} //= $value{$_} for grep { defined $value{$_} } keys %value;
  return;
}

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
