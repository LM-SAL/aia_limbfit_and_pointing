use v5.38;
use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub perl_quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

sub write_masterpoint ($dir, $name) {
  my $path = "$dir/$name";
  open my $fh, '>', $path or die "Cannot write $path: $!";
  print {$fh} "KWD A_171_X0\t1.25\nKWD A_171_Y0\t-2.50\n";
  close $fh or die "Cannot close $path: $!";
  return $path;
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );

my $stage = "$tmp/stage";
make_path($stage);

my $masterpoint = "$stage/masterpoint_20260501_0130_3hcadence.txt";
open my $mp_fh, '>', $masterpoint or die "Cannot write $masterpoint: $!";
print {$mp_fh} "KWD A_171_X0\t1.25\n";
print {$mp_fh} "KWD A_171_Y0\t-2.50\n";
close $mp_fh or die "Cannot close $masterpoint: $!";

my $stale = "$stage/masterpoint_20260501_0130_3hcadence.txt.bak";
open my $stale_fh, '>', $stale or die "Cannot write $stale: $!";
print {$stale_fh} "KWD A_999_X0\t999\n";
close $stale_fh or die "Cannot close $stale: $!";

my $drms = "$tmp/drms";
my $bin  = "$drms/bin/linux_avx2";
make_path( $bin, "$drms/lib/linux_avx2", "$drms/include" );

my $show_info = "$bin/show_info";
open my $show_fh, '>', $show_info or die "Cannot write $show_info: $!";
print {$show_fh} <<'PERL';
#!/usr/bin/env perl
use v5.38;

if ($ENV{SHOW_INFO_LOG}) {
  open my $log_fh, '>>', $ENV{SHOW_INFO_LOG} or die "Cannot write SHOW_INFO_LOG: $!";
  print {$log_fh} join("\t", @ARGV), "\n";
  close $log_fh or die "Cannot close SHOW_INFO_LOG: $!";
}

my $query = join q{ }, @ARGV;
my $scenario = $ENV{SHOW_INFO_SCENARIO} // 'default';

if ($query =~ /sdo[.]master_pointing/) {
  print "T_START\tT_STOP\tDATE\tVERSION\tSAT_ROT\n";
  print "2026-05-01T00:00:00Z\t2026-05-01T03:00:00Z\t2026-05-01T00:00:00Z\t0\t42\n";
}
elsif ($query =~ /test[.]series/) {
  my ($exact) = $query =~ /test[.]series\[([^]]+)\]/;
  my %records = (
    '2026-05-01T00:00:00Z' => [ '2026-05-01T06:00:00Z', '2026-05-01T00:00:00Z', 0 ],
    '2026-05-01T06:00:00Z' => [ '2026-05-01T12:00:00Z', '2026-05-01T00:00:00Z', 0 ],
  );
  my $record;
  if ($scenario eq 'version0' && $exact eq '2026-05-01T00:00:00Z') {
    $record = [ '2026-05-01T03:00:00Z', '2026-05-01T00:00:00Z', 0 ];
  }
  elsif ($scenario eq 'version1' && $exact eq '2026-05-01T00:00:00Z') {
    $record = [ '2026-05-01T04:30:00Z', '2026-05-01T00:00:00Z', 1 ];
  }
  elsif ($scenario eq 'stale' && $exact eq '2026-05-01T00:00:00Z') {
    $record = [ '2026-05-01T03:00:00Z', '2099-01-01T00:00:00Z', 1 ];
  }
  elsif ($scenario eq 'consecutive' && $exact eq '2026-05-01T00:00:00Z') {
    $record = $records{$exact};
  }
  elsif ($scenario eq 'missing_middle' && $exact eq '2026-05-01T00:00:00Z') {
    $record = $records{$exact};
  }
  elsif ($scenario eq 'already_finalized' && $exact eq '2026-05-01T00:00:00Z') {
    $record = [ '2026-05-01T03:00:00Z', '2026-05-01T00:00:00Z', 0 ];
  }
  elsif ($scenario eq 'delayed' && $exact eq '2026-05-01T00:00:00Z') {
    $record = $records{$exact};
  }
  elsif ($scenario eq 'delayed' && $exact eq '2026-05-01T06:00:00Z') {
    $record = $records{$exact};
  }

  if ($scenario eq 'partial_version1' && $exact eq '2026-05-01T00:00:00Z') {
    print "T_START\tT_STOP\tDATE\tVERSION\tA_171_X0\tA_171_Y0\tA_193_X0\tA_193_Y0\n";
    print "$exact\t2026-05-01T03:00:00Z\t2026-05-01T00:00:00Z\t1\t0.50\t-0.75\t9.00\t10.00\n";
  }

  elsif ($scenario eq 'previous_version1' && $exact eq '2026-05-01T00:00:00Z') {
    print "T_START\tT_STOP\tDATE\tVERSION\tA_171_X0\tA_171_Y0\n";
    print "$exact\t2026-05-01T06:00:00Z\t2026-05-01T00:00:00Z\t1\t0.50\t-0.75\n";
  }
  elsif ($record) {
    print "T_START\tT_STOP\tDATE\tVERSION\n";
    print "$exact\t$record->[0]\t$record->[1]\t$record->[2]\n";
  }
}
exit 0;
PERL
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $set_info = "$bin/set_info";
open my $set_fh, '>', $set_info or die "Cannot write $set_info: $!";
print {$set_fh} "#!/usr/bin/env perl\nexit 99;\n";
close $set_fh or die "Cannot close $set_info: $!";
chmod 0755, $set_info or die "Cannot chmod $set_info: $!";

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use v5.38;\nreturn {\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$cfg_fh} "  set_info => ",  perl_quote($set_info),  ",\n";
print {$cfg_fh} "  mpt_series => 'test.series',\n";
print {$cfg_fh} "  sdo_series => 'sdo.master_pointing',\n";
print {$cfg_fh} "  pointing_dir => ", perl_quote($stage), ",\n";
print {$cfg_fh} "  cadence_h => 3,\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;

# Baseline: no existing target record
my $query_log = "$tmp/show_info.log";
local $ENV{SHOW_INFO_LOG} = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'default';

my $output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
my $exit   = $? >> 8;

is( $exit, 0, 'update3h_mpt.pl dry run exits successfully' ) or diag $output;
like( $output, qr/\bT_START=2026-05-01T00:00:00Z\b/, 'dry run writes corrected slot start' );
like( $output, qr/\bT_STOP=2026-05-01T06:00:00Z\b/,   'new record provisionally covers six hours' );
like( $output, qr/\bA_171_X0=1[.]25\b/,               'dry run includes X keyword from masterpoint file' );
like( $output, qr/\bA_171_Y0=-2[.]50\b/,              'dry run includes Y keyword from masterpoint file' );
unlike( $output, qr/\bA_999_X0=999\b/,                'dry run ignores stale backup-like masterpoint files' );

open my $log_fh, '<', $query_log or die "Cannot read $query_log: $!";
my $queries = do { local $/; <$log_fh> };
close $log_fh or die "Cannot close $query_log: $!";

my $expected_drms_time   = '$(2026-05-01T00:00:00Z)';
my $unexpected_drms_time = '$(2026-05-01T01:30:00Z)';
like(
  $queries,
  qr/\Q$expected_drms_time\E/,
  'show_info queries use corrected slot start'
);
unlike(
  $queries,
  qr/\Q$unexpected_drms_time\E/,
  'show_info queries do not use filename center time'
);
unlike( $queries, qr/test[.]series\[\?T_START<=/, 'target lookups are not contains-time queries' );
like( $queries, qr/test[.]series\[2026-05-01T00:00:00Z\]/,
  'target lookup selects the exact T_START' );

# VERSION=0 existing record: update in-place, no duplicate create
unlink $query_log;
local $ENV{SHOW_INFO_LOG} = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'version0';

$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'VERSION=0 dry run exits successfully' ) or diag $output;
like( $output, qr/ds=test\.series\[2026-05-01T00:00:00Z\]/,
  'VERSION=0 triggers update of existing record' );
like( $output, qr/\bVERSION=1\b/,
  'VERSION=0 sets VERSION=1 on update' );
like( $output, qr/\bA_171_X0=1[.]25\b/, 'VERSION=0 update includes repaired X keyword' );
like( $output, qr/\bA_171_Y0=-2[.]50\b/, 'VERSION=0 update includes repaired Y keyword' );
unlike( $output, qr/\bset_info\s+-c\b/, 'VERSION=0 does not create duplicate record' );

# VERSION=1 existing record: create new with VERSION=2, correct T_STOP
unlink $query_log;
local $ENV{SHOW_INFO_LOG} = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'version1';

$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'VERSION=1 dry run exits successfully' ) or diag $output;
like( $output, qr/\bset_info\s+-c\b/, 'VERSION=1 triggers create of new record' );
like( $output, qr/\bVERSION=2\b/, 'VERSION=1 increments to VERSION=2' );
like( $output, qr/\bT_STOP=2026-05-01T06:00:00Z\b/, 'VERSION=1 uses provisional six-hour T_STOP' );
unlike( $output, qr/\bT_STOP=2026-05-01T04:30:00Z\b/, 'VERSION=1 does not inherit wrong T_STOP from existing record' );

# Stale record (age guard): skip entirely
unlink $query_log;
local $ENV{SHOW_INFO_LOG} = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'stale';

$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'stale record dry run exits successfully' ) or diag $output;
unlike( $output, qr/\bset_info\b/, 'stale record skips all set_info commands' );

# Consecutive successful slots: the new slot gets six hours and the exact
# predecessor is shortened to three hours.
my $held_masterpoint = "$masterpoint.hold";
rename $masterpoint, $held_masterpoint or die "Cannot hold $masterpoint: $!";
my $next_masterpoint = write_masterpoint( $stage, 'masterpoint_20260501_0430_3hcadence.txt' );
local $ENV{SHOW_INFO_SCENARIO} = 'consecutive';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'consecutive-success dry run exits successfully' ) or diag $output;
like( $output, qr/\bT_START=2026-05-01T03:00:00Z\b/, 'future slot starts at the next cadence' );
like( $output, qr/\bT_STOP=2026-05-01T09:00:00Z\b/, 'future slot gets provisional six-hour coverage' );
like(
  $output,
  qr/ds=test[.]series\[2026-05-01T00:00:00Z\].*T_STOP=2026-05-01T03:00:00Z/s,
  'successful future slot shortens the exact predecessor'
);
unlink $next_masterpoint or die "Cannot remove $next_masterpoint: $!";
rename $held_masterpoint, $masterpoint or die "Cannot restore $masterpoint: $!";

# A missing immediate slot keeps the older row provisional, preserving its
# coverage across the failed three-hour window.
rename $masterpoint, $held_masterpoint or die "Cannot hold $masterpoint: $!";
my $later_masterpoint = write_masterpoint( $stage, 'masterpoint_20260501_0730_3hcadence.txt' );
local $ENV{SHOW_INFO_SCENARIO} = 'missing_middle';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'missing-middle dry run exits successfully' ) or diag $output;
like( $output, qr/\bT_START=2026-05-01T06:00:00Z\b/, 'later successful slot is published' );
like( $output, qr/\bT_STOP=2026-05-01T12:00:00Z\b/, 'later slot gets six-hour coverage' );
unlike(
  $output,
  qr/ds=test[.]series\[2026-05-01T00:00:00Z\].*T_STOP=2026-05-01T03:00:00Z/s,
  'missing immediate predecessor does not shorten the older fallback row'
);
unlink $later_masterpoint or die "Cannot remove $later_masterpoint: $!";
rename $held_masterpoint, $masterpoint or die "Cannot restore $masterpoint: $!";

# Retrying a slot whose predecessor is already finalized is idempotent.
rename $masterpoint, $held_masterpoint or die "Cannot hold $masterpoint: $!";
$next_masterpoint = write_masterpoint( $stage, 'masterpoint_20260501_0430_3hcadence.txt' );
local $ENV{SHOW_INFO_SCENARIO} = 'already_finalized';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'already-finalized dry run exits successfully' ) or diag $output;
unlike(
  $output,
  qr/ds=test[.]series\[2026-05-01T00:00:00Z\].*T_STOP=2026-05-01T03:00:00Z/s,
  'already-finalized predecessor is not rewritten'
);
unlink $next_masterpoint or die "Cannot remove $next_masterpoint: $!";
rename $held_masterpoint, $masterpoint or die "Cannot restore $masterpoint: $!";

# A versioned predecessor is replaced with its own pointing values intact.
rename $masterpoint, $held_masterpoint or die "Cannot hold $masterpoint: $!";
$next_masterpoint = write_masterpoint( $stage, 'masterpoint_20260501_0430_3hcadence.txt' );
local $ENV{SHOW_INFO_SCENARIO} = 'previous_version1';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'versioned-predecessor dry run exits successfully' ) or diag $output;
like( $output, qr/\bVERSION=2\b/, 'versioned predecessor increments VERSION' );
like( $output, qr/A_171_X0=0[.]50.*A_171_Y0=-0[.]75/s,
  'versioned predecessor keeps its own pointing values' );
unlink $next_masterpoint or die "Cannot remove $next_masterpoint: $!";
rename $held_masterpoint, $masterpoint or die "Cannot restore $masterpoint: $!";

# A delayed repair sees its already-recorded successor and is canonicalized to
# a three-hour row immediately.
rename $masterpoint, $held_masterpoint or die "Cannot hold $masterpoint: $!";
$next_masterpoint = write_masterpoint( $stage, 'masterpoint_20260501_0430_3hcadence.txt' );
local $ENV{SHOW_INFO_SCENARIO} = 'delayed';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'delayed-repair dry run exits successfully' ) or diag $output;
like( $output, qr/\bT_START=2026-05-01T03:00:00Z\b/, 'delayed repair publishes the missing slot' );
like( $output, qr/\bT_STOP=2026-05-01T06:00:00Z\b/, 'existing successor canonicalizes delayed repair to three hours' );
like(
  $output,
  qr/ds=test[.]series\[2026-05-01T00:00:00Z\].*T_STOP=2026-05-01T03:00:00Z/s,
  'delayed repair shortens its exact predecessor'
);
unlink $next_masterpoint or die "Cannot remove $next_masterpoint: $!";
rename $held_masterpoint, $masterpoint or die "Cannot restore $masterpoint: $!";

# Off-grid masterpoint filename: skip with warning
my $bad_stage = "$tmp/bad_stage";
make_path($bad_stage);
my $bad_mp = "$bad_stage/masterpoint_20260501_0130_1hcadence.txt";
open my $bad_fh, '>', $bad_mp or die "Cannot write $bad_mp: $!";
print {$bad_fh} "KWD A_171_X0\t1.25\n";
close $bad_fh or die "Cannot close $bad_mp: $!";

my $bad_config = "$tmp/bad_config.pl";
open my $bad_cfg_fh, '>', $bad_config or die "Cannot write $bad_config: $!";
print {$bad_cfg_fh} "use v5.38;\nreturn {\n";
print {$bad_cfg_fh} "  tz => 'UTC',\n";
print {$bad_cfg_fh} "  sumserver => 'test',\n";
print {$bad_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$bad_cfg_fh} "  set_info => ",  perl_quote($set_info),  ",\n";
print {$bad_cfg_fh} "  mpt_series => 'test.series',\n";
print {$bad_cfg_fh} "  sdo_series => 'sdo.master_pointing',\n";
print {$bad_cfg_fh} "  pointing_dir => ", perl_quote($bad_stage), ",\n";
print {$bad_cfg_fh} "  cadence_h => 3,\n";
print {$bad_cfg_fh} "};\n";
close $bad_cfg_fh or die "Cannot close $bad_config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $bad_config;
local $ENV{SHOW_INFO_SCENARIO} = 'default';

$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$bad_stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'off-grid dry run exits successfully' ) or diag $output;
like( $output, qr/Skipping.*invalid slot/, 'off-grid masterpoint is skipped' );
unlike( $output, qr/\bset_info\b/, 'off-grid masterpoint triggers no set_info' );

# A partial repair is allowed only for an existing record and keeps all
# unmentioned wavelength values when creating the next version.
my $partial_config = "$tmp/partial_config.pl";
open my $partial_cfg_fh, '>', $partial_config or die "Cannot write $partial_config: $!";
print {$partial_cfg_fh} "use v5.38;\nreturn {\n";
print {$partial_cfg_fh} "  tz => 'UTC', sumserver => 'test', cadence_h => 3, wl => [171, 193],\n";
print {$partial_cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$partial_cfg_fh} "  set_info => ",  perl_quote($set_info),  ",\n";
print {$partial_cfg_fh} "  mpt_series => 'test.series', sdo_series => 'sdo.master_pointing',\n";
print {$partial_cfg_fh} "  pointing_dir => ", perl_quote($stage), ",\n};\n";
close $partial_cfg_fh or die "Cannot close $partial_config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $partial_config;
local $ENV{SHOW_INFO_SCENARIO} = 'partial_version1';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'partial repair of an existing row succeeds' ) or diag $output;
like( $output, qr/\bA_171_X0=1[.]25\b/, 'partial repair replaces the requested value' );
like( $output, qr/\bA_193_X0=9[.]00\b/, 'partial repair preserves an unmentioned wavelength' );
like( $output, qr/\bVERSION=2\b/, 'partial repair creates the next version' );

local $ENV{SHOW_INFO_SCENARIO} = 'default';
$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
isnt( $exit, 0, 'partial repair cannot create a missing row' );
like( $output, qr{requires an existing record}, 'missing-row refusal is explicit' );

done_testing;
