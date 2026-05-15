use v5.42;
use FindBin    qw($Bin);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub perl_quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $drms = "$tmp/drms";
make_path(
  "$drms/bin/linux_avx2", "$drms/lib/linux_avx2", "$drms/include/base", "$drms/scripts",
  "$drms/src",
);

# Fake show_info emits T_START T_STOP A_094_X0 A_094_Y0 per line.
# Scenarios without wavelength problems use valid numeric values.
my $show_info = "$drms/bin/linux_avx2/show_info";
open my $show_fh, '>', $show_info or die "Cannot write $show_info: $!";
print {$show_fh} "#!/usr/bin/env perl\n";
print {$show_fh} "use v5.42;\n";
print {$show_fh} "if (\$ENV{SHOW_INFO_LOG}) {\n";
print {$show_fh}
  "  open my \$log_fh, '>>', \$ENV{SHOW_INFO_LOG} or die \"Cannot write SHOW_INFO_LOG: \$!\";\n";
print {$show_fh} "  print {\$log_fh} join(\"\\t\", \@ARGV), \"\\n\";\n";
print {$show_fh} "  close \$log_fh or die \"Cannot close SHOW_INFO_LOG: \$!\";\n";
print {$show_fh} "}\n";
print {$show_fh} "my \$scenario = \$ENV{SHOW_INFO_SCENARIO} || 'no_gap';\n";
print {$show_fh} "if (\$scenario eq 'single_gap') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T06:00:00Z 2026-05-01T09:00:00Z 960.7 1024.5\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'large_gap') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T08:00:00Z 2026-05-01T11:00:00Z 960.8 1024.6\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'multi_gap') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T09:00:00Z 2026-05-01T12:00:00Z 960.9 1024.7\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'two_gaps') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T06:00:00Z 2026-05-01T09:00:00Z 960.7 1024.5\\n};\n";
print {$show_fh} "  print qq{2026-05-01T12:00:00Z 2026-05-01T15:00:00Z 960.9 1024.7\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'overlapping_spans') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T06:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T03:00:00Z 2026-05-01T09:00:00Z 960.6 1024.4\\n};\n";
print {$show_fh} "  print qq{2026-05-01T06:00:00Z 2026-05-01T12:00:00Z 960.7 1024.5\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'wl_gap') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T03:00:00Z 2026-05-01T06:00:00Z NaN NaN\\n};\n";
print {$show_fh} "} else {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 960.5 1024.3\\n};\n";
print {$show_fh} "  print qq{2026-05-01T03:00:00Z 2026-05-01T06:00:00Z 960.6 1024.4\\n};\n";
print {$show_fh} "}\n";
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use v5.42;\nreturn {\n";
print {$cfg_fh} "  wl => [94],\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$cfg_fh} "  cadence_h => 3,\n";
print {$cfg_fh} "  nan_sentinel => 1234567,\n";
print {$cfg_fh} "  check_gaps_dir => ", perl_quote("$tmp/check"), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;
my $query_log = "$tmp/show_info.log";
local $ENV{SHOW_INFO_LOG}      = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'no_gap';
my $output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully with contiguous records' )
  or diag $output;
like( $output, qr{No gaps detected}, 'contiguous records report no gaps' );

unlink $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'no_gap';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl no-arg default run exits successfully' ) or diag $output;

open my $log_fh, '<', $query_log or die "Cannot read $query_log: $!";
my $queries = do { local $/; <$log_fh> };
close $log_fh or die "Cannot close $query_log: $!";
like(
  $queries,
  qr{test[.]master_pointing3h\[2010[.]11[.]01_00:00-},
  'no-arg default query starts at explicit 2010-11-01 00:00'
);
like(
  $queries,
  qr{key=T_START,T_STOP,A_094_X0,A_094_Y0\b},
  'query requests T_START, T_STOP, and per-wavelength keywords'
);

ok( -e "$tmp/check/patch.txt", 'patch file is created in check directory' );

my $fake_run = "$tmp/fake_run_limbfit.pl";
open my $run_fh, '>', $fake_run or die "Cannot write $fake_run: $!";
print {$run_fh} "#!/usr/bin/env perl\n";
print {$run_fh} "use v5.42;\nuse File::Path qw(make_path);\n";
print {$run_fh} "my %args;\n";
print {$run_fh} "for my \$arg (\@ARGV) { \$args{\$1} = \$2 if \$arg =~ /^-(\\w+)=(.*)\$/; }\n";
print {$run_fh}
"if (\$ENV{FAKE_RUN_LOG}) { open my \$log_fh, '>>', \$ENV{FAKE_RUN_LOG} or die \"Cannot write FAKE_RUN_LOG: \$!\"; print {\$log_fh} (\$args{series} // q{}), \"\\n\"; close \$log_fh or die \"Cannot close FAKE_RUN_LOG: \$!\"; }\n";
print {$run_fh}
"exit 3 if defined \$ENV{FAKE_RUN_FAIL_HOUR} && \$args{hour} == \$ENV{FAKE_RUN_FAIL_HOUR} && (\$args{series} // q{}) eq 'aia.lev1';\n";
print {$run_fh}
"my \$dir = sprintf '%s/%d/%02d/%02d', \$args{outroot}, \$args{year}, \$args{month}, \$args{day};\n";
print {$run_fh} "make_path(\$dir);\n";
print {$run_fh}
"my \$path = sprintf '%s/%d%02d%02d_%02d_0094.limb', \$dir, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
print {$run_fh} "open my \$fh, '>', \$path or die \"Cannot write \$path: \$!\";\n";
print {$run_fh} "print {\$fh} \"ok\\n\" if (\$args{series} // q{}) eq 'aia.lev1';\n";
print {$run_fh} "close \$fh or die \"Cannot close \$path: \$!\";\n";
print {$run_fh} "exit 0;\n";
close $run_fh or die "Cannot close $fake_run: $!";
chmod 0755, $fake_run or die "Cannot chmod $fake_run: $!";

my $fake_reduce = "$tmp/fake_reduce.pl";
open my $reduce_fh, '>', $fake_reduce or die "Cannot write $fake_reduce: $!";
print {$reduce_fh} "#!/usr/bin/env perl\n";
print {$reduce_fh} "use v5.42;\nuse File::Path qw(make_path);\n";
print {$reduce_fh} "my %args;\n";
print {$reduce_fh} "for my \$arg (\@ARGV) { \$args{\$1} = \$2 if \$arg =~ /^-(\\w+)=(.*)\$/; }\n";
print {$reduce_fh}
"my \$path = sprintf '%s/%d/%02d/%02d/%d%02d%02d_%02d_0094.limb', \$args{inpdir}, \$args{year}, \$args{month}, \$args{day}, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
print {$reduce_fh} "die \"missing limb\\n\" unless -s \$path;\n";
print {$reduce_fh} "make_path(\$args{outdir});\n";
print {$reduce_fh}
"my \$out = sprintf '%s/masterpoint_%d%02d%02d_%02d00_3hcadence.txt', \$args{outdir}, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
print {$reduce_fh} "open my \$fh, '>', \$out or die \"Cannot write \$out: \$!\";\n";
print {$reduce_fh} "print {\$fh} \"ok\\n\";\n";
print {$reduce_fh} "close \$fh or die \"Cannot close \$out: \$!\";\n";
print {$reduce_fh} "exit 0;\n";
close $reduce_fh or die "Cannot close $fake_reduce: $!";
chmod 0755, $fake_reduce or die "Cannot chmod $fake_reduce: $!";

# Fake single-wavelength limbfit: creates the limb file unconditionally.
my $fake_test = "$tmp/fake_run_test.pl";
open my $test_fh, '>', $fake_test or die "Cannot write $fake_test: $!";
print {$test_fh} "#!/usr/bin/env perl\n";
print {$test_fh} "use v5.42;\nuse File::Path qw(make_path);\n";
print {$test_fh} "my %args;\n";
print {$test_fh} "for my \$arg (\@ARGV) { \$args{\$1} = \$2 if \$arg =~ /^-(\\w+)=(.*)\$/; }\n";
print {$test_fh}
"my \$dir = sprintf '%s/%d/%02d/%02d', \$args{outroot}, \$args{year}, \$args{month}, \$args{day};\n";
print {$test_fh} "make_path(\$dir);\n";
print {$test_fh}
"my \$path = sprintf '%s/%d%02d%02d_%02d_%04d.limb', \$dir, \$args{year}, \$args{month}, \$args{day}, \$args{hour}, \$args{wavel};\n";
print {$test_fh} "open my \$fh, '>', \$path or die \"Cannot write \$path: \$!\";\n";
print {$test_fh} "print {\$fh} \"ok\\n\";\n";
print {$test_fh} "close \$fh or die \"Cannot close \$path: \$!\";\n";
print {$test_fh} "exit 0;\n";
close $test_fh or die "Cannot close $fake_test: $!";
chmod 0755, $fake_test or die "Cannot chmod $fake_test: $!";

my $fake_plot = "$tmp/fake_plot.sh";
open my $plot_fh, '>', $fake_plot or die "Cannot write $fake_plot: $!";
print {$plot_fh} "#!/bin/sh\nexit 0\n";
close $plot_fh or die "Cannot close $fake_plot: $!";
chmod 0755, $fake_plot or die "Cannot chmod $fake_plot: $!";

my $gap_config = "$tmp/gap_config.pl";
open my $gap_cfg_fh, '>', $gap_config or die "Cannot write $gap_config: $!";
print {$gap_cfg_fh} "use v5.42;\nreturn {\n";
print {$gap_cfg_fh} "  wl => [94],\n";
print {$gap_cfg_fh} "  tz => 'UTC',\n";
print {$gap_cfg_fh} "  sumserver => 'test',\n";
print {$gap_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$gap_cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$gap_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$gap_cfg_fh} "  cadence_h => 3,\n";
print {$gap_cfg_fh} "  nan_sentinel => 1234567,\n";
print {$gap_cfg_fh} "  check_gaps_dir => ",   perl_quote("$tmp/gap_check"), ",\n";
print {$gap_cfg_fh} "  run_limbfit_ymdh => ", perl_quote($fake_run),        ",\n";
print {$gap_cfg_fh} "  run_limbfit_test => ", perl_quote($fake_test),       ",\n";
print {$gap_cfg_fh} "  lf2mpr_nrt => ",       perl_quote($fake_reduce),     ",\n";
print {$gap_cfg_fh} "  plot_limb => ",        perl_quote($fake_plot),       ",\n";
print {$gap_cfg_fh} "};\n";
close $gap_cfg_fh or die "Cannot close $gap_config: $!";

# --- temporal gap (single slot) ---
my $run_log = "$tmp/gap_run.log";
local $ENV{AIA_LIMBFIT_CONFIG} = $gap_config;
local $ENV{SHOW_INFO_SCENARIO} = 'single_gap';
local $ENV{FAKE_RUN_LOG}       = $run_log;
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully for single-slot gap' )
  or diag $output;
like(
  $output,
  qr{TEMPORAL GAP\s+2026-05-01T00:00:00Z\s+->\s+2026-05-01T06:00:00Z\s+\(6\.00 h\)},
  'single-slot gap is reported'
);
like( $output, qr{Temporal gaps: 1},  'temporal gap count is summarized' );
like( $output, qr{Backfill slots: 1}, 'single-slot gap triggers one backfill' );
like(
  $output,
  qr{No valid limb outputs for 2026-5-1 3:00 with aia[.]lev1_nrt2; retrying with aia[.]lev1},
  'empty-output slot retries with aia.lev1'
);
like( $output, qr{Reduced slot using aia[.]lev1}, 'fallback slot reduces successfully' );
ok(
  -s "$tmp/gap_check/stage/masterpoint_20260501_0300_3hcadence.txt",
  'backfill reducer writes staged masterpoint output'
);

open my $run_log_fh, '<', $run_log or die "Cannot read $run_log: $!";
my @run_series = <$run_log_fh>;
close $run_log_fh or die "Cannot close $run_log: $!";
chomp @run_series;
is_deeply(
  \@run_series,
  [ 'aia.lev1_nrt2', 'aia.lev1' ],
  'backfill tries lev1_nrt2 first then falls back to aia.lev1'
);

# --- non-multiple gap: report only, no backfill ---
local $ENV{SHOW_INFO_SCENARIO} = 'large_gap';
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully for non-multiple gap' ) or diag $output;
like(
  $output,
  qr{TEMPORAL GAP\s+2026-05-01T00:00:00Z\s+->\s+2026-05-01T08:00:00Z\s+\(8\.00 h\)},
  'non-multiple-of-cadence gap is reported'
);
unlike( $output, qr{run_limbfit_ymdh[.]pl}, 'non-multiple gap does not trigger backfill' );

# --- multi-slot gap (6h = 2x cadence): backfills both slots ---
# Wrapped in do{} so local AIA_LIMBFIT_CONFIG doesn't leak into subsequent tests.
my $multi_config = "$tmp/multi_config.pl";
do {
  open my $multi_cfg_fh, '>', $multi_config or die "Cannot write $multi_config: $!";
  print {$multi_cfg_fh} "use v5.42;\nreturn {\n";
  print {$multi_cfg_fh} "  wl => [94],\n";
  print {$multi_cfg_fh} "  tz => 'UTC',\n";
  print {$multi_cfg_fh} "  sumserver => 'test',\n";
  print {$multi_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
  print {$multi_cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
  print {$multi_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
  print {$multi_cfg_fh} "  cadence_h => 3,\n";
  print {$multi_cfg_fh} "  nan_sentinel => 1234567,\n";
  print {$multi_cfg_fh} "  check_gaps_dir => ",   perl_quote("$tmp/multi_check"), ",\n";
  print {$multi_cfg_fh} "  run_limbfit_ymdh => ", perl_quote($fake_run),          ",\n";
  print {$multi_cfg_fh} "  run_limbfit_test => ", perl_quote($fake_test),         ",\n";
  print {$multi_cfg_fh} "  lf2mpr_nrt => ",       perl_quote($fake_reduce),       ",\n";
  print {$multi_cfg_fh} "  plot_limb => ",        perl_quote($fake_plot),         ",\n";
  print {$multi_cfg_fh} "};\n";
  close $multi_cfg_fh or die "Cannot close $multi_config: $!";

  local $ENV{AIA_LIMBFIT_CONFIG} = $multi_config;
  local $ENV{SHOW_INFO_SCENARIO} = 'multi_gap';
  my $multi_out =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
  is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully for multi-slot gap' )
    or diag $multi_out;
  like(
    $multi_out,
    qr{TEMPORAL GAP\s+2026-05-01T00:00:00Z\s+->\s+2026-05-01T09:00:00Z\s+\(9\.00 h\)},
    'multi-slot gap is reported'
  );
  like( $multi_out, qr{-hour=3\b}, 'multi-slot gap backfills first missing slot' );
  like( $multi_out, qr{-hour=6\b}, 'multi-slot gap backfills second missing slot' );
};

# --- overlapping 6h-span records staggered 3h apart: T_START diffs == cadence, no gap ---
local $ENV{SHOW_INFO_SCENARIO} = 'overlapping_spans';
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully for overlapping-span records' )
  or diag $output;
like( $output, qr{No gaps detected}, '6h-span records staggered 3h apart produce no gap' );

# --- -report-only suppresses backfill ---
local $ENV{SHOW_INFO_SCENARIO} = 'single_gap';
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -report-only -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl -report-only exits successfully' ) or diag $output;
like( $output, qr{TEMPORAL GAP}, '-report-only still prints gap' );
unlike( $output, qr{run_limbfit_ymdh[.]pl}, '-report-only suppresses backfill commands' );

# --- wavelength gap ---
local $ENV{SHOW_INFO_SCENARIO} = 'wl_gap';
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully for wavelength gap' ) or diag $output;
like(
  $output,
  qr{MISSING WAVELENGTHS\s+2026-05-01T03:00:00Z:\s+94},
  'wavelength gap record is reported'
);
like( $output, qr{Wavelength gaps: 1}, 'wavelength gap count is summarized' );
ok( -s "$tmp/gap_check/patch.txt", 'patch file is written for wavelength gap' );

open my $patch_fh, '<', "$tmp/gap_check/patch.txt" or die "Cannot read patch.txt: $!";
my $patch = do { local $/; <$patch_fh> };
close $patch_fh or die "Cannot close patch.txt: $!";
like(
  $patch,
  qr{2026-05-01T03:00:00Z\s+94\s+NaN\s+NaN},
  'patch file contains wavelength gap entry'
);

ok(
  -s "$tmp/gap_check/limb/2026/05/01/20260501_03_0094.limb",
  'run_limbfit_test creates limb file for missing wavelength'
);

# --- backfill failure continues to next slot ---
my $continue_config = "$tmp/continue_config.pl";
open my $continue_cfg_fh, '>', $continue_config or die "Cannot write $continue_config: $!";
print {$continue_cfg_fh} "use v5.42;\nreturn {\n";
print {$continue_cfg_fh} "  wl => [94],\n";
print {$continue_cfg_fh} "  tz => 'UTC',\n";
print {$continue_cfg_fh} "  sumserver => 'test',\n";
print {$continue_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$continue_cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$continue_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$continue_cfg_fh} "  cadence_h => 3,\n";
print {$continue_cfg_fh} "  nan_sentinel => 1234567,\n";
print {$continue_cfg_fh} "  check_gaps_dir => ",   perl_quote("$tmp/continue_check"), ",\n";
print {$continue_cfg_fh} "  run_limbfit_ymdh => ", perl_quote($fake_run),             ",\n";
print {$continue_cfg_fh} "  run_limbfit_test => ", perl_quote($fake_test),            ",\n";
print {$continue_cfg_fh} "  lf2mpr_nrt => ",       perl_quote($fake_reduce),          ",\n";
print {$continue_cfg_fh} "  plot_limb => ",        perl_quote($fake_plot),            ",\n";
print {$continue_cfg_fh} "};\n";
close $continue_cfg_fh or die "Cannot close $continue_config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $continue_config;
local $ENV{SHOW_INFO_SCENARIO} = 'two_gaps';
local $ENV{FAKE_RUN_FAIL_HOUR} = 3;
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl continues after one failed backfill slot' )
  or diag $output;
like(
  $output,
  qr{Backfill failed for 2026-5-1 3:00 UTC; continuing: No valid limb files generated},
  'failed backfill slot is reported without stopping the range'
);
like( $output, qr{Backfill failures: 1}, 'failed backfill count is summarized' );
like(
  $output,
  qr{Failed backfill slots:\s+2026-05-01 03:00 UTC: No valid limb files generated},
  'failed backfill slots are listed in the final summary'
);
ok(
  -s "$tmp/continue_check/stage/masterpoint_20260501_0900_3hcadence.txt",
  'later backfill slot is still reduced after an earlier slot fails'
);

done_testing;
