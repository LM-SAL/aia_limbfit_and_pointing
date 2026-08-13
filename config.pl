use v5.38;

# Central configuration for the AIA limbfit / pointing NRT pipeline.
# Load with: my $cfg = do "$FindBin::RealBin/config.pl" or die "Cannot load config.pl: " . ($@ || $!);
return {

  # AIA wavelengths processed by the pipeline
  wl => [ 94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500 ],

  # JSOC / SGE environment
  sumserver => 'k1',
  sge_root  => '/SGE',
  tz        => 'UTC',

  # Executables
  perl_bin    => '/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl',
  limbfit_exe => '/homef/nabil/JSOC-orig/bin/linux_avx2/limbfit_aia',
  set_info    => '/homef/nabil/JSOC-orig/bin/linux_avx2/set_info',
  show_info   => '/homef/nabil/JSOC-orig/bin/linux_avx2/show_info',

  drms_root_dir           => '/homef/nabil/JSOC-orig',
  drms_params_install_dir => '/homef/nabil/JSOC-orig/include/base',
  drms_scrs_install_dir   => '/homef/nabil/JSOC-orig/scripts',
  drms_src_install_dir    => '/homef/nabil/JSOC-orig/src',

  # DRMS series and query - NRT
  lev1_series              => 'aia.lev1_nrt2',
  lev1_nrt2_retention_days => 14,
  mpt_series               => 'aia.master_pointing3h',
  sdo_series               => 'sdo.master_pointing',

  # Reject frames containing 99 or more missing pixels.
  drms_filter => q{[?MISSVALS<99?]},

  # 397312 == 0x61000: reject non-science pointing (0x1000),
  # ISS-open (0x20000), and calibration frames (0x40000).
  drms_quality_filter => '[?(QUALITY & 397312)=0?]',

  # Deployment paths - NRT
  fits_root    => '/surge40/nabil/LimbFit_c/fits_nrt',
  logs_dir     => '/surge40/nabil/LimbFit_c/logs_nrt',
  pointing_dir => '/surge40/nabil/LimbFit_c/stage',

  # Deployment paths - gap check
  check_gaps_dir => '/surge40/nabil/LimbFit_c/gaps',

  # Pipeline constants
  cadence_h => 3,

  # Physical-data calibration controls for lf2mpr_nrt.pdl.
  sigma_clip_pass1_sigma => 2,
  sigma_clip_pass2_sigma => 3,

  # A split must leave two useful segments whose centers are far apart relative
  # to their internal scatter.
  split_cluster_min_segment_size => 20,
  split_cluster_separation_ratio => 10,

  nan_sentinel => 1_234_567,
  mail_to      => 'nabil',
};
