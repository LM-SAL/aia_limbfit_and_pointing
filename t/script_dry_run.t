use strict;
use warnings;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use Test::More;

sub perl_quote {
  my ($value) = @_;
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $cfg  = "$tmp/config.pl";

open my $cfg_fh, '>', $cfg or die "Cannot write $cfg: $!";
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  wl => [94, 171, 4500],\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  sge_root => '/SGE',\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  drms_root_dir => '/drms',\n";
print {$cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$cfg_fh} "  fits_root => ", perl_quote("$tmp/fits"), ",\n";
print {$cfg_fh} "  test_fits_root => ", perl_quote("$tmp/testfits"), ",\n";
print {$cfg_fh} "  update_dir => ", perl_quote("$tmp/update"), ",\n";
print {$cfg_fh} "  logs_dir => ", perl_quote("$tmp/logs"), ",\n";
print {$cfg_fh} "  repo_root => '/repo',\n";
print {$cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$cfg_fh} "  mpt_series => 'aia.master_pointing3h',\n";
print {$cfg_fh} "  limbfit_exe => '/bin/limbfit',\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;

my $out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'run_limbfit_ymdh.pl dry-run exits successfully' ) or diag $out;
like( $out, qr{/bin/limbfit dsinp='aia[.]lev1_nrt2\[2026[.]05[.]01_03/3h\]\[\?WAVELNTH=94\?\]\[\?MISSVALS<99\?\]' sum=5}, 'ymdh dry-run prints 94A command' );
like( $out, qr{20260501_03_4500[.]limb}, 'ymdh dry-run includes 4500A output path' );

$out = qx("$^X" "$repo/run_limbfit_test.pl" -dry-run -no-plots -year=2026 -month=5 -day=1 -hour=3 -wavel=171 2>&1);
is( $? >> 8, 0, 'run_limbfit_test.pl dry-run exits successfully' ) or diag $out;
like( $out, qr{/bin/limbfit dsinp='aia[.]lev1\[2026[.]05[.]01_03/3h\]\[\?WAVELNTH=171\?\]\[\?MISSVALS<99\?\]' sum=5}, 'test dry-run prints requested wavelength command' );
like( $out, qr{20260501_03_0171[.]limb}, 'test dry-run includes padded output filename' );
unlike( $out, qr{plot_limb[.]py}, 'test dry-run suppresses plot command with -no-plots' );

$out = qx("$^X" "$repo/run_limbfit_test.pl" -dry-run -no-plots -year=2026 -month=5 -day=1 -wavel=171 2>&1);
isnt( $? >> 8, 0, 'run_limbfit_test.pl rejects a missing hour' );
like( $out, qr{Missing required option: --hour}, 'missing-hour error is explicit' );
unlike( $out, qr{uninitialized value}, 'missing-hour error avoids Perl warnings' );

$out = qx(printf '2026-05-01T03:00:00Z 171 NaN NaN\n' | "$^X" "$repo/update_nans.pl" -dry-run 2>&1);
is( $? >> 8, 0, 'update_nans.pl dry-run exits successfully' ) or diag $out;
unlike( $out, qr{\bsed\b}, 'update_nans dry-run does not depend on an external sed script' );
like( $out, qr{lf2mpr_nrt[.]pdl -inpdir .*-outdir .* -y 2026 -mo 5 -da 1 -h 3 -require-all}, 'update_nans dry-run prints strict reducer command' );
like( $out, qr{update3h_mpt[.]pl -src .*-ser aia[.]master_pointing3h}, 'update_nans dry-run prints update command' );

$out = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'cron_submit_slot.pl dry-run exits successfully' ) or diag $out;
is(
  $out,
  "/repo/pipeline_slot_nrt.csh 2026 5 1 3 > $tmp/logs/20260501_03.log 2>&1\n",
  'cron dry-run prints pipeline command'
);

$out = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=4 2>&1);
is( $? >> 8, 0, 'cron_submit_slot.pl skipped dry-run exits successfully' ) or diag $out;
is( $out, q{}, 'cron dry-run prints nothing for off-cadence hour' );

my $fail_limbfit = "$tmp/fail_limbfit.pl";
open my $fail_fh, '>', $fail_limbfit or die "Cannot write $fail_limbfit: $!";
print {$fail_fh} "#!/usr/bin/env perl\n";
print {$fail_fh} "use strict;\nuse warnings;\nexit 3;\n";
close $fail_fh or die "Cannot close $fail_limbfit: $!";
chmod 0755, $fail_limbfit or die "Cannot chmod $fail_limbfit: $!";

my $fail_cfg = "$tmp/fail_config.pl";
open my $fail_cfg_fh, '>', $fail_cfg or die "Cannot write $fail_cfg: $!";
print {$fail_cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$fail_cfg_fh} "  wl => [94],\n";
print {$fail_cfg_fh} "  sumserver => 'test',\n";
print {$fail_cfg_fh} "  sge_root => '/SGE',\n";
print {$fail_cfg_fh} "  drms_root_dir => '/drms',\n";
print {$fail_cfg_fh} "  drms_params_install_dir => '/drms/include/base',\n";
print {$fail_cfg_fh} "  drms_scrs_install_dir => '/drms/scripts',\n";
print {$fail_cfg_fh} "  drms_src_install_dir => '/drms/src',\n";
print {$fail_cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$fail_cfg_fh} "  fits_root => ", perl_quote("$tmp/failfits"), ",\n";
print {$fail_cfg_fh} "  test_fits_root => ", perl_quote("$tmp/failtest"), ",\n";
print {$fail_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$fail_cfg_fh} "  limbfit_exe => ", perl_quote($fail_limbfit), ",\n";
print {$fail_cfg_fh} "};\n";
close $fail_cfg_fh or die "Cannot close $fail_cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $fail_cfg;
$out = qx("$^X" "$repo/run_limbfit_ymdh.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
isnt( $? >> 8, 0, 'run_limbfit_ymdh.pl fails after a limbfit failure' );
like( $out, qr{limbfit_aia failed for 94A}, 'ymdh failure is reported' );
ok( !-e "$tmp/failfits/2026/05/01/20260501_03_0094.limb", 'ymdh removes failed limbfit output file' );

$out = qx("$^X" "$repo/run_limbfit_test.pl" -no-plots -year=2026 -month=5 -day=1 -hour=3 -wavel=94 2>&1);
isnt( $? >> 8, 0, 'run_limbfit_test.pl fails after a limbfit failure' );
ok( !-e "$tmp/failtest/2026/05/01/20260501_03_0094.limb",
  'single-wavelength runner removes failed output file' );

done_testing;
