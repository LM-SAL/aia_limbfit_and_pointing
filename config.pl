use v5.42;

# Central configuration for the AIA limbfit / pointing NRT pipeline.
# Load with: my $cfg = do "$FindBin::RealBin/config.pl" or die "Cannot load config.pl: " . ($@ || $!);
return {

  # AIA wavelengths processed by the pipeline
  wl => [ 94, 131, 171, 193, 211, 304, 335, 1600, 1700, 4500 ],

  # JSOC / SGE environment
  sumserver => 'k1',
  sge_root  => '/SGE',
  sge_queue => 'k.q',
  tz        => 'UTC',

  # Executables
  perl_bin    => '/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl',
  qsub        => '/SGE/bin/lx24-amd64/qsub2',
  limbfit_exe => '/homef/nabil/JSOC-orig/bin/linux_avx2/limbfit_aia',
  set_info    => '/homef/nabil/JSOC-orig/bin/linux_avx2/set_info',
  show_info   => '/homef/nabil/JSOC-orig/bin/linux_avx2/show_info',

  drms_root_dir           => '/homef/nabil/JSOC-orig',
  drms_params_install_dir => '/homef/nabil/JSOC-orig/include/base',
  drms_scrs_install_dir   => '/homef/nabil/JSOC-orig/scripts',
  drms_src_install_dir    => '/homef/nabil/JSOC-orig/src',

  # DRMS series and query - NRT
  lev1_series     => 'aia.lev1_nrt2',
  lev1_nrt2_start => '2022-06-08T06:34:53Z',
  mpt_series      => 'aia.master_pointing3h',
  sdo_series      => 'sdo.master_pointing',
  drms_filter     => '[?MISSVALS<99?]',

  # Deployment paths - NRT
  repo_root      => '/homef/nabil/Git/aia_limbfit_and_pointing',
  fits_root      => '/surge40/nabil/LimbFit_c/fits_nrt',
  test_fits_root => '/surge40/nabil/LimbFit_c/Ctest',
  logs_dir       => '/surge40/nabil/LimbFit_c/logs_nrt',
  pointing_dir   => '/surge40/nabil/LimbFit_c/stage',

  # Deployment paths - gap check
  check_gaps_dir => '/surge40/nabil/LimbFit_c/gaps',

  # Deployment paths - NaN gap-fill
  update_dir => '/surge40/nabil/LimbFit_c/Update',

  # Pipeline constants
  cadence_h => 3,

  # Sigma-clipping controls for lf2mpr_nrt.pdl.
  # `zero` uses the historical radial cutoff at N * sigma.
  # `mean` uses mean(distance) + N * sigma.
  sigma_clip_pass1_baseline => 'zero',
  sigma_clip_pass2_baseline => 'mean',
  sigma_clip_pass1_sigma    => 2,
  sigma_clip_pass2_sigma    => 3,

  # Split-cluster detection controls for lf2mpr_nrt.pdl.
  # `fail` aborts when a file contains two large, well-separated temporal
  # segments; `ignore` disables that safeguard.
  split_cluster_mode             => 'fail',
  split_cluster_min_segment_size => 20,
  split_cluster_jump_sigma       => 6,
  split_cluster_jump_ratio       => 3,
  split_cluster_separation_ratio => 10,

  nan_sentinel => 1_234_567,
  mail_to      => 'nabil',
};
