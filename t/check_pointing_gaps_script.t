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
print {$show_fh} "my \$scenario = \$ENV{SHOW_INFO_SCENARIO} || 'invalid_short';\n";
print {$show_fh} "if (\$scenario eq 'invalid_multislot') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 10 20\\n};\n";
print {$show_fh} "  print qq{2026-05-01T03:00:00Z 2026-05-01T09:00:00Z 11 21\\n};\n";
print {$show_fh} "  print qq{2026-05-01T09:00:00Z 2026-05-01T12:00:00Z 12 22\\n};\n";
print {$show_fh} "} elsif (\$scenario eq 'temporal_gap') {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 10 20\\n};\n";
print {$show_fh} "  print qq{2026-05-01T06:00:00Z 2026-05-01T09:00:00Z 11 21\\n};\n";
print {$show_fh} "} else {\n";
print {$show_fh} "  print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 10 20\\n};\n";
print {$show_fh} "  print qq{2026-05-01T03:00:00Z 2026-05-01T04:30:00Z 11 21\\n};\n";
print {$show_fh} "  print qq{2026-05-01T04:30:00Z 2026-05-01T04:30:00Z 12 22\\n};\n";
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
print {$cfg_fh} "  fits_root => ",      perl_quote("$tmp/fits"),  ",\n";
print {$cfg_fh} "  check_gaps_dir => ", perl_quote("$tmp/check"), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;
my $query_log = "$tmp/show_info.log";
local $ENV{SHOW_INFO_LOG}      = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'invalid_short';
my $output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl exits successfully with fake show_info' ) or diag $output;

like(
  $output,
qr{INVALID SLOT\s+2026-05-01T03:00:00Z\s+->\s+2026-05-01T04:30:00Z\s+\([^)]*wrong_duration[^)]*off_grid_stop[^)]*\)},
  '90-minute record is reported as an invalid slot'
);
like(
  $output,
qr{INVALID SLOT\s+2026-05-01T04:30:00Z\s+->\s+2026-05-01T04:30:00Z\s+\([^)]*non_positive_duration[^)]*off_grid_start[^)]*off_grid_stop[^)]*\)},
  'same-start-stop record is reported as an invalid slot'
);
like( $output, qr{Slot issues: 2}, 'invalid slot count is summarized' );
unlike( $output, qr{run_limbfit_ymdh[.]pl},
  'invalid records alone do not trigger backfill commands' );
ok( -e "$tmp/check/patch.txt", 'patch file is created in check directory' );

local $ENV{SHOW_INFO_SCENARIO} = 'invalid_multislot';
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -dry-run -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl dry-run handles multi-slot invalid records' )
  or diag $output;
like(
  $output,
  qr{INVALID SLOT\s+2026-05-01T03:00:00Z\s+->\s+2026-05-01T09:00:00Z\s+\(wrong_duration\)},
  'multi-slot invalid record is reported'
);
like(
  $output,
  qr{run_limbfit_ymdh[.]pl -year=2026 -month=5 -day=1 -hour=3\b},
  'multi-slot invalid record backfills first 3-hour slot'
);
like(
  $output,
  qr{run_limbfit_ymdh[.]pl -year=2026 -month=5 -day=1 -hour=6\b},
  'multi-slot invalid record backfills second 3-hour slot'
);
unlike(
  $output,
  qr{run_limbfit_ymdh[.]pl -year=2026 -month=5 -day=1 -hour=9\b},
  'multi-slot invalid record does not create an extra slot past T_STOP'
);

unlink $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'invalid_short';
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
print {$run_fh} "my \$dir = sprintf '%s/%d/%02d/%02d', \$args{outroot}, \$args{year}, \$args{month}, \$args{day};\n";
print {$run_fh} "make_path(\$dir);\n";
print {$run_fh} "my \$path = sprintf '%s/%d%02d%02d_%02d_0094.limb', \$dir, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
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
print {$reduce_fh} "my \$path = sprintf '%s/%d/%02d/%02d/%d%02d%02d_%02d_0094.limb', \$args{inpdir}, \$args{year}, \$args{month}, \$args{day}, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
print {$reduce_fh} "die \"missing limb\\n\" unless -s \$path;\n";
print {$reduce_fh} "make_path(\$args{outdir});\n";
print {$reduce_fh} "my \$out = sprintf '%s/masterpoint_%d%02d%02d_%02d00_3hcadence.txt', \$args{outdir}, \$args{year}, \$args{month}, \$args{day}, \$args{hour};\n";
print {$reduce_fh} "open my \$fh, '>', \$out or die \"Cannot write \$out: \$!\";\n";
print {$reduce_fh} "print {\$fh} \"ok\\n\";\n";
print {$reduce_fh} "close \$fh or die \"Cannot close \$out: \$!\";\n";
print {$reduce_fh} "exit 0;\n";
close $reduce_fh or die "Cannot close $fake_reduce: $!";
chmod 0755, $fake_reduce or die "Cannot chmod $fake_reduce: $!";

my $fake_plot = "$tmp/fake_plot.sh";
open my $plot_fh, '>', $fake_plot or die "Cannot write $fake_plot: $!";
print {$plot_fh} "#!/bin/sh\nexit 0\n";
close $plot_fh or die "Cannot close $fake_plot: $!";
chmod 0755, $fake_plot or die "Cannot chmod $fake_plot: $!";

my $fallback_config = "$tmp/fallback_config.pl";
open my $fallback_cfg_fh, '>', $fallback_config or die "Cannot write $fallback_config: $!";
print {$fallback_cfg_fh} "use v5.42;\nreturn {\n";
print {$fallback_cfg_fh} "  wl => [94],\n";
print {$fallback_cfg_fh} "  tz => 'UTC',\n";
print {$fallback_cfg_fh} "  sumserver => 'test',\n";
print {$fallback_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$fallback_cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$fallback_cfg_fh} "  lev1_series => 'aia.lev1_nrt2',\n";
print {$fallback_cfg_fh} "  cadence_h => 3,\n";
print {$fallback_cfg_fh} "  nan_sentinel => 1234567,\n";
print {$fallback_cfg_fh} "  fits_root => ",      perl_quote("$tmp/fallback_fits"),  ",\n";
print {$fallback_cfg_fh} "  check_gaps_dir => ", perl_quote("$tmp/fallback_check"), ",\n";
print {$fallback_cfg_fh} "  run_limbfit_ymdh => ", perl_quote($fake_run), ",\n";
print {$fallback_cfg_fh} "  lf2mpr_nrt => ", perl_quote($fake_reduce), ",\n";
print {$fallback_cfg_fh} "  plot_limb => ", perl_quote($fake_plot), ",\n";
print {$fallback_cfg_fh} "};\n";
close $fallback_cfg_fh or die "Cannot close $fallback_config: $!";

my $run_log = "$tmp/fallback_run.log";
local $ENV{AIA_LIMBFIT_CONFIG} = $fallback_config;
local $ENV{SHOW_INFO_SCENARIO} = 'temporal_gap';
local $ENV{FAKE_RUN_LOG}       = $run_log;
$output =
qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'check_pointing_gaps.pl retries with aia.lev1 when default series yields empty limbs' )
  or diag $output;
like(
  $output,
  qr{No valid limb outputs for 2026-5-1 3:00 with aia[.]lev1_nrt2; retrying with aia[.]lev1},
  'empty-output slot retries with aia.lev1'
);
like(
  $output,
  qr{Reduced slot using aia[.]lev1},
  'fallback slot reduces successfully with aia.lev1'
);
ok(
  -s "$tmp/fallback_check/stage/masterpoint_20260501_0300_3hcadence.txt",
  'fallback reducer writes staged masterpoint output'
);

open my $run_log_fh, '<', $run_log or die "Cannot read $run_log: $!";
my @run_series = <$run_log_fh>;
close $run_log_fh or die "Cannot close $run_log: $!";
chomp @run_series;
is_deeply(
  \@run_series,
  [ 'aia.lev1_nrt2', 'aia.lev1' ],
  'fallback slot tries default series first and then aia.lev1'
);

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
print {$continue_cfg_fh} "  fits_root => ",      perl_quote("$tmp/continue_fits"),  ",\n";
print {$continue_cfg_fh} "  check_gaps_dir => ", perl_quote("$tmp/continue_check"), ",\n";
print {$continue_cfg_fh} "  run_limbfit_ymdh => ", perl_quote($fake_run), ",\n";
print {$continue_cfg_fh} "  lf2mpr_nrt => ", perl_quote($fake_reduce), ",\n";
print {$continue_cfg_fh} "  plot_limb => ", perl_quote($fake_plot), ",\n";
print {$continue_cfg_fh} "};\n";
close $continue_cfg_fh or die "Cannot close $continue_config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $continue_config;
local $ENV{SHOW_INFO_SCENARIO} = 'invalid_multislot';
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
  -s "$tmp/continue_check/stage/masterpoint_20260501_0600_3hcadence.txt",
  'later backfill slot is still reduced after an earlier slot fails'
);

done_testing;
