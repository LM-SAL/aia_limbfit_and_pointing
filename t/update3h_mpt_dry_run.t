use v5.42;
use FindBin qw($Bin);
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
use v5.42;

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
  if ($scenario eq 'version0') {
    print "T_START\tT_STOP\tDATE\tVERSION\n";
    print "2026-05-01T00:00:00Z\t2026-05-01T03:00:00Z\t2026-05-01T00:00:00Z\t0\n";
  }
  elsif ($scenario eq 'version1') {
    print "T_START\tT_STOP\tDATE\tVERSION\n";
    print "2026-05-01T00:00:00Z\t2026-05-01T04:30:00Z\t2026-05-01T00:00:00Z\t1\n";
  }
  elsif ($scenario eq 'stale') {
    print "T_START\tT_STOP\tDATE\tVERSION\n";
    print "2026-05-01T00:00:00Z\t2026-05-01T03:00:00Z\t2099-01-01T00:00:00Z\t1\n";
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
print {$cfg_fh} "use v5.42;\nreturn {\n";
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
like( $output, qr/\bT_STOP=2026-05-01T03:00:00Z\b/,   'dry run writes corrected slot stop' );
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
like( $output, qr/\bT_STOP=2026-05-01T03:00:00Z\b/, 'VERSION=1 uses correct T_STOP from masterpoint, not inherited wrong value' );
unlike( $output, qr/\bT_STOP=2026-05-01T04:30:00Z\b/, 'VERSION=1 does not inherit wrong T_STOP from existing record' );

# Stale record (age guard): skip entirely
unlink $query_log;
local $ENV{SHOW_INFO_LOG} = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'stale';

$output = `$^X "$repo/update3h_mpt.pl" -dry-run -srcdir "$stage" -series test.series 2>&1`;
$exit   = $? >> 8;
is( $exit, 0, 'stale record dry run exits successfully' ) or diag $output;
unlike( $output, qr/\bset_info\b/, 'stale record skips all set_info commands' );

# Off-grid masterpoint filename: skip with warning
my $bad_stage = "$tmp/bad_stage";
make_path($bad_stage);
my $bad_mp = "$bad_stage/masterpoint_20260501_0130_1hcadence.txt";
open my $bad_fh, '>', $bad_mp or die "Cannot write $bad_mp: $!";
print {$bad_fh} "KWD A_171_X0\t1.25\n";
close $bad_fh or die "Cannot close $bad_mp: $!";

my $bad_config = "$tmp/bad_config.pl";
open my $bad_cfg_fh, '>', $bad_config or die "Cannot write $bad_config: $!";
print {$bad_cfg_fh} "use v5.42;\nreturn {\n";
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

done_testing;
