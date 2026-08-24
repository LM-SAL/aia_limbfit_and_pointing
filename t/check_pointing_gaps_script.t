use v5.38;
use FindBin qw($Bin);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $drms = "$tmp/drms";
make_path(
  "$drms/bin/linux_avx2", "$drms/lib/linux_avx2", "$drms/include/base", "$drms/scripts",
  "$drms/src"
);
my $show_info = "$drms/bin/linux_avx2/show_info";
open my $show_fh, '>', $show_info or die "Cannot write $show_info: $!";
print {$show_fh} <<'FAKE';
#!/usr/bin/env perl
use v5.38;
if ($ENV{SHOW_INFO_LOG}) {
  open my $fh, '>>', $ENV{SHOW_INFO_LOG} or die $!;
  print {$fh} join("\t", @ARGV), "\n";
  close $fh;
}
my $scenario = $ENV{SHOW_INFO_SCENARIO} // 'no_gap';
if (grep { $_ eq '-cq' } @ARGV) {
  print(($ENV{SHOW_INFO_LEV1_COUNT} // 1), "\n");
  exit 0;
}
if ($scenario eq 'covered') {
  print "2026-05-01T00:00:00Z 2026-05-01T06:00:00Z 1 2\n";
  print "2026-05-01T06:00:00Z 2026-05-01T12:00:00Z 1 2\n";
} elsif ($scenario eq 'covered_day') {
  print "2026-03-06T00:00:00Z 2026-03-07T00:00:00Z 1 2\n";
  print "2026-03-07T00:00:00Z 2026-03-08T00:00:00Z 1 2\n";
} elsif ($scenario eq 'partly_covered_gap') {
  print "2026-05-01T00:00:00Z 2026-05-01T06:00:00Z 1 2\n";
  print "2026-05-01T09:00:00Z 2026-05-01T12:00:00Z 1 2\n";
} elsif ($scenario eq 'gap') {
  print "2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 1 2\n";
  print "2026-05-01T06:00:00Z 2026-05-01T09:00:00Z 1 2\n";
} elsif ($scenario eq 'wavelength') {
  print "2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 1 2\n";
  print "2026-05-01T03:00:00Z 2026-05-01T06:00:00Z NaN NaN\n";
} else {
  print "2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 1 2\n";
  print "2026-05-01T03:00:00Z 2026-05-01T06:00:00Z 1 2\n";
}
FAKE
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $fits = "$tmp/fits";
my $gaps = "$tmp/gaps";
my $cfg  = "$tmp/config.pl";
open my $cfg_fh, '>', $cfg or die "Cannot write $cfg: $!";
print {$cfg_fh} "use v5.38;\nreturn {\n";
print {$cfg_fh} "  wl => [94], cadence_h => 3, nan_sentinel => 1234567,\n";
print {$cfg_fh} "  tz => 'UTC', sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", quote($show_info), ",\n";
print {$cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$cfg_fh} "  lev1_series => 'aia.lev1_nrt2', lev1_nrt2_retention_days => 14,\n";
print {$cfg_fh} "  fits_root => ",      quote($fits), ",\n";
print {$cfg_fh} "  check_gaps_dir => ", quote($gaps), ",\n";
print {$cfg_fh} "  perl_bin => ",       quote($^X),   ",\n";
print {$cfg_fh} "  split_cluster_min_segment_size => 20,\n";
print {$cfg_fh} "  split_cluster_separation_ratio => 10,\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;
my $args = '-year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1';

local $ENV{SHOW_INFO_SCENARIO} = 'no_gap';
my $output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
is( $? >> 8, 0, 'contiguous report succeeds' ) or diag $output;
like( $output, qr{No gaps detected}, 'contiguous report is clean' );
ok( !-e $gaps, 'report creates no workspace' );

local $ENV{SHOW_INFO_SCENARIO} = 'covered';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{No gaps detected}, 'six-hour record covers a six-hour start interval' );

local $ENV{SHOW_INFO_SCENARIO} = 'covered_day';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{No gaps detected}, '24-hour record covers a 24-hour start interval' );

local $ENV{SHOW_INFO_SCENARIO} = 'partly_covered_gap';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{Backfill slots: 1}, 'six-hour predecessor leaves only one uncovered slot' );
like( $output, qr{run_limbfit_ymdh[.]pl .*hour=6}, 'repair begins after six-hour coverage' );
unlike( $output, qr{run_limbfit_ymdh[.]pl .*hour=3}, 'covered cadence is not proposed' );

local $ENV{SHOW_INFO_SCENARIO} = 'gap';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{TEMPORAL GAP.*00:00:00Z -> .*06:00:00Z}, 'uncovered slot is reported' );
like( $output, qr{Backfill slots: 1}, 'one repair slot is counted' );
like( $output, qr{run_limbfit_ymdh[.]pl .*hour=3.*outroot=\Q$gaps/20260501_03/limb\E},
  'report prints isolated limb-fit command' );
like( $output, qr{run_limbfit_ymdh[.]pl .*series=aia[.]lev1\b},
  'historical repair uses the durable Level-1 series' );
like( $output, qr{lf2mpr_nrt[.]pdl .*outdir=\Q$gaps/20260501_03/stage\E},
  'report prints reducer command' );
like(
  $output,
  qr{interpolate-previous=2026-05-01T00:00:00Z -interpolate-next=2026-05-01T06:00:00Z},
  'report prints the bracketing interpolation fallback'
);
unlike( $output, qr{PIPELINE START|LIMBFIT START}, 'report executes no repair command' );
unlike( $output, qr{LEV1 94 A}, 'available Level-1 data prints no warning' );

{
  local $ENV{SHOW_INFO_LEV1_COUNT} = 0;
  $output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
  like( $output, qr{# LEV1 94 A: no aia[.]lev1 records}, 'missing Level-1 data is reported' );
  like( $output, qr{# No aia[.]lev1 data; interpolate}, 'unfittable slot points at the fallback' );
  unlike( $output, qr{run_limbfit_ymdh[.]pl|physically bad|inpdir=},
    'unfittable slot gets no limb-fit or reducer command' );
  like( $output, qr{interpolate-previous=.*\n.*update3h_mpt[.]pl .*-dry-run\n.*update3h_mpt[.]pl .*stage\n},
    'unfittable slot keeps the fallback and publish commands' );
}

local $ENV{SHOW_INFO_SCENARIO} = 'wavelength';
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{MISSING WAVELENGTHS.*94}, 'missing masterpoint wavelength is reported' );
like( $output, qr{LIMB 94 A: missing or empty}, 'missing source limb is explained' );

my $split_path = "$fits/2026/05/01/20260501_03_0094.limb";
make_path("$fits/2026/05/01");
copy( "$repo/data/20260326_18_0094.limb", $split_path ) or die "Cannot copy fixture: $!";
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{reducer failed: Split-cluster detected.*split after row 88, segments 88/92},
  'existing split limb is diagnosed' );
like( $output, qr{head -n 88 .*0094[.]limb}, 'first segment repair command is printed' );
like( $output, qr{tail -n [+]89 .*0094[.]limb}, 'second segment repair command is printed' );
ok( !-e $gaps, 'diagnosis remains read-only' );

open my $usable_fh, '>', $split_path or die "Cannot replace $split_path: $!";
print {$usable_fh} "10 20\n" for 1 .. 40;
close $usable_fh or die "Cannot close $split_path: $!";
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args 2>&1);
like( $output, qr{LIMB 94 A: usable}, 'existing usable limb is recognized' );
like( $output, qr{lf2mpr_nrt[.]pdl .*inpdir=\Q$fits\E.*-wavel=94},
  'usable wavelength gets a partial repair command' );
unlike( $output, qr{run_limbfit_ymdh[.]pl}, 'usable wavelength is not regenerated' );

my $commands = "$tmp/commands.sh";
$output = qx("$^X" "$repo/check_pointing_gaps.pl" $args -commands="$commands" 2>&1);
like( $output, qr{LIMB 94 A: usable}, 'report still goes to stdout with -commands' );
open my $commands_fh, '<', $commands or die "Cannot read $commands: $!";
my $commands_text = do { local $/; <$commands_fh> };
close $commands_fh;
like( $commands_text, qr{lf2mpr_nrt[.]pdl .*-wavel=94}, 'commands file holds the repair command' );
like( $commands_text, qr{update3h_mpt[.]pl .*stage\n}, 'commands file holds the publish command' );
unlike( $commands_text, qr{MISSING WAVELENGTHS|LIMB 94}, 'commands file holds no diagnostics' );

done_testing;
