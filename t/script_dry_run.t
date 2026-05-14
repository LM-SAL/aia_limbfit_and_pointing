use v5.42;
use FindBin    qw($Bin);
use File::Temp qw(tempdir);
use Test::More;

sub perl_quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $cfg  = "$tmp/config.pl";

open my $cfg_fh, '>', $cfg or die "Cannot write $cfg: $!";
print {$cfg_fh} "use v5.42;\nreturn {\n";
print {$cfg_fh} "  wl => [94, 4500],\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  sge_root => '/SGE',\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  drms_root_dir => '/drms',\n";
print {$cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$cfg_fh} "  fits_root => ",      perl_quote("$tmp/fits"),     ",\n";
print {$cfg_fh} "  test_fits_root => ", perl_quote("$tmp/testfits"), ",\n";
print {$cfg_fh} "  update_dir => ",     perl_quote("$tmp/update"),   ",\n";
print {$cfg_fh} "  logs_dir => ",       perl_quote("$tmp/logs"),     ",\n";
print {$cfg_fh} "  repo_root => '/repo',\n";
print {$cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$cfg_fh} "  mpt_series => 'aia.master_pointing3h',\n";
print {$cfg_fh} "  limbfit_exe => '/bin/limbfit',\n";
print {$cfg_fh} "  lf_sed => '/tmp/lf.sed',\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;

my $out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'run_limbfit_ymdh.pl dry-run exits successfully' ) or diag $out;
like(
  $out,
qr{/bin/limbfit dsinp='aia[.]lev1_nrt2\[2026[.]05[.]01_03/3h\]\[\?WAVELNTH=94\?\]\[\?MISSVALS<99\?\]' sum=5},
  'ymdh dry-run prints 94A command'
);
like( $out, qr{20260501_03_4500[.]limb}, 'ymdh dry-run includes 4500A output path' );

$out =
qx("$^X" "$repo/run_limbfit_test.pl" -dry-run -no-plots -year=2026 -month=5 -day=1 -hour=3 -wavel=171 2>&1);
is( $? >> 8, 0, 'run_limbfit_test.pl dry-run exits successfully' ) or diag $out;
like(
  $out,
qr{/bin/limbfit dsinp='aia[.]lev1\[2026[.]05[.]01_03/3h\]\[\?WAVELNTH=171\?\]\[\?MISSVALS<99\?\]' sum=5},
  'test dry-run prints requested wavelength command'
);
like( $out, qr{20260501_03_0171[.]limb}, 'test dry-run includes padded output filename' );
unlike( $out, qr{plot_limb[.]py}, 'test dry-run suppresses plot command with -no-plots' );

$out = qx(printf '2026-05-01T03:00:00Z 171 NaN NaN\n' | "$^X" "$repo/update_nans.pl" -dry-run 2>&1);
is( $? >> 8, 0, 'update_nans.pl dry-run exits successfully' ) or diag $out;
like(
  $out,
  qr{sed -i -f /tmp/lf[.]sed .*/20260501_03_0171[.]limb},
  'update_nans dry-run prints sed command'
);
like(
  $out,
  qr{lf2mpr_nrt[.]pdl -inpdir .*-outdir .* -y 2026 -mo 5 -da 1 -h 3},
  'update_nans dry-run prints reducer command'
);
like(
  $out,
  qr{update3h_mpt[.]pl -src .*-ser aia[.]master_pointing3h},
  'update_nans dry-run prints update command'
);

$out = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'cron_submit_slot.pl dry-run exits successfully' ) or diag $out;
is(
  $out,
  "/repo/pipeline_slot_nrt.csh 2026 5 1 3 > $tmp/logs/20260501_03.log 2>&1\n",
  'cron dry-run prints pipeline command'
);

$out = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=4 2>&1);
is( $? >> 8, 0,   'cron_submit_slot.pl skipped dry-run exits successfully' ) or diag $out;
is( $out,    q{}, 'cron dry-run prints nothing for off-cadence hour' );

my $fail_limbfit = "$tmp/fail_limbfit.pl";
open my $fail_fh, '>', $fail_limbfit or die "Cannot write $fail_limbfit: $!";
print {$fail_fh} "#!/usr/bin/env perl\n";
print {$fail_fh} "use v5.42;\nexit 3;\n";
close $fail_fh or die "Cannot close $fail_limbfit: $!";
chmod 0755, $fail_limbfit or die "Cannot chmod $fail_limbfit: $!";

my $mixed_limbfit = "$tmp/mixed_limbfit.pl";
open my $mixed_fh, '>', $mixed_limbfit or die "Cannot write $mixed_limbfit: $!";
print {$mixed_fh} "#!/usr/bin/env perl\n";
print {$mixed_fh} "use v5.42;\n";
print {$mixed_fh} "my \$args = join q{ }, \@ARGV;\n";
print {$mixed_fh} "exit 3 if \$args =~ /WAVELNTH=94/;\n";
print {$mixed_fh} "print qq{ok\\n};\n";
print {$mixed_fh} "exit 0;\n";
close $mixed_fh or die "Cannot close $mixed_limbfit: $!";
chmod 0755, $mixed_limbfit or die "Cannot chmod $mixed_limbfit: $!";

my $empty_limbfit = "$tmp/empty_limbfit.pl";
open my $empty_fh, '>', $empty_limbfit or die "Cannot write $empty_limbfit: $!";
print {$empty_fh} "#!/usr/bin/env perl\n";
print {$empty_fh} "use v5.42;\nexit 0;\n";
close $empty_fh or die "Cannot close $empty_limbfit: $!";
chmod 0755, $empty_limbfit or die "Cannot chmod $empty_limbfit: $!";

my $mixed_cfg = "$tmp/mixed_config.pl";
open my $mixed_cfg_fh, '>', $mixed_cfg or die "Cannot write $mixed_cfg: $!";
print {$mixed_cfg_fh} "use v5.42;\nreturn {\n";
print {$mixed_cfg_fh} "  wl => [94, 171],\n";
print {$mixed_cfg_fh} "  sumserver => 'test',\n";
print {$mixed_cfg_fh} "  sge_root => '/SGE',\n";
print {$mixed_cfg_fh} "  drms_root_dir => '/drms',\n";
print {$mixed_cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$mixed_cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$mixed_cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$mixed_cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$mixed_cfg_fh} "  fits_root => ", perl_quote("$tmp/mixedfits"), ",\n";
print {$mixed_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$mixed_cfg_fh} "  limbfit_exe => ", perl_quote($mixed_limbfit), ",\n";
print {$mixed_cfg_fh} "};\n";
close $mixed_cfg_fh or die "Cannot close $mixed_cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $mixed_cfg;
$out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'run_limbfit_ymdh.pl succeeds when at least one wavelength succeeds' ) or diag $out;
like( $out, qr{limbfit_aia failed for 94A}, 'ymdh partial failure is reported' );
ok(
  !-e "$tmp/mixedfits/2026/05/01/20260501_03_0094.limb",
  'ymdh removes failed partial-run output file'
);
ok(
  -s "$tmp/mixedfits/2026/05/01/20260501_03_0171.limb",
  'ymdh keeps successful partial-run output file'
);

my $empty_cfg = "$tmp/empty_config.pl";
open my $empty_cfg_fh, '>', $empty_cfg or die "Cannot write $empty_cfg: $!";
print {$empty_cfg_fh} "use v5.42;\nreturn {\n";
print {$empty_cfg_fh} "  wl => [94],\n";
print {$empty_cfg_fh} "  sumserver => 'test',\n";
print {$empty_cfg_fh} "  sge_root => '/SGE',\n";
print {$empty_cfg_fh} "  drms_root_dir => '/drms',\n";
print {$empty_cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$empty_cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$empty_cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$empty_cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$empty_cfg_fh} "  fits_root => ", perl_quote("$tmp/emptyfits"), ",\n";
print {$empty_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$empty_cfg_fh} "  limbfit_exe => ", perl_quote($empty_limbfit), ",\n";
print {$empty_cfg_fh} "};\n";
close $empty_cfg_fh or die "Cannot close $empty_cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $empty_cfg;
$out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
cmp_ok( $? >> 8, '!=', 0, 'run_limbfit_ymdh.pl fails when every wavelength writes empty output' )
  or diag $out;
like( $out, qr{empty output file}, 'ymdh empty output failure is reported' );
ok( !-e "$tmp/emptyfits/2026/05/01/20260501_03_0094.limb", 'ymdh removes empty output file' );

my $fail_cfg = "$tmp/fail_config.pl";
open my $fail_cfg_fh, '>', $fail_cfg or die "Cannot write $fail_cfg: $!";
print {$fail_cfg_fh} "use v5.42;\nreturn {\n";
print {$fail_cfg_fh} "  wl => [94],\n";
print {$fail_cfg_fh} "  sumserver => 'test',\n";
print {$fail_cfg_fh} "  sge_root => '/SGE',\n";
print {$fail_cfg_fh} "  drms_root_dir => '/drms',\n";
print {$fail_cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$fail_cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$fail_cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$fail_cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$fail_cfg_fh} "  fits_root => ", perl_quote("$tmp/failfits"), ",\n";
print {$fail_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$fail_cfg_fh} "  limbfit_exe => ", perl_quote($fail_limbfit), ",\n";
print {$fail_cfg_fh} "};\n";
close $fail_cfg_fh or die "Cannot close $fail_cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $fail_cfg;
$out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
cmp_ok( $? >> 8, '!=', 0, 'run_limbfit_ymdh.pl fails when every wavelength fails' ) or diag $out;
like( $out, qr{limbfit_aia failed for 94A},  'ymdh all-failed run reports the wavelength failure' );
like( $out, qr{failed for every wavelength}, 'ymdh all-failed run reports slot failure' );
ok(
  !-e "$tmp/failfits/2026/05/01/20260501_03_0094.limb",
  'ymdh removes failed all-run output file'
);

done_testing;
