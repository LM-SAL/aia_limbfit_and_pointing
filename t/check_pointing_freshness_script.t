use v5.38;
use FindBin    qw($Bin);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use Time::Local qw(timegm);

sub quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $bin  = "$tmp/bin";
my $drms = "$tmp/drms";
make_path( $bin, "$drms/bin/linux_avx2", "$drms/lib/linux_avx2", "$drms/include/base",
  "$drms/scripts", "$drms/src" );

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
my $scenario = $ENV{SHOW_INFO_SCENARIO} // 'fresh';
if ($scenario eq 'fresh') {
  print "2026-09-10T10:02:11Z 2026-09-07T12:00:00Z 2026-09-07T15:00:00Z\n";
} elsif ($scenario eq 'stale') {
  print "2026-09-08T13:02:11Z 2026-09-07T12:00:00Z 2026-09-07T18:00:00Z\n";
  print "2026-09-08T01:00:00Z 2026-09-07T09:00:00Z 2026-09-07T12:00:00Z\n";
} elsif ($scenario eq 'gap') {
  print "2026-09-08T00:00:00Z 2026-09-05T00:00:00Z 2026-09-05T06:00:00Z\n";
  print "2026-09-08T01:00:00Z 2026-09-05T09:00:00Z 2026-09-05T12:00:00Z\n";
  print "2026-09-08T02:00:00Z 2026-09-05T12:00:00Z 2026-09-05T18:00:00Z\n";
  print "2026-09-08T03:00:00Z 2026-09-05T18:00:00Z 2026-09-06T00:00:00Z\n";
  print "2026-09-10T08:00:00Z 2026-09-06T00:00:00Z 2026-09-06T06:00:00Z\n";
} elsif ($scenario eq 'nodate') {
  print "\t2026-09-09T00:00:00Z\t2026-09-09T03:00:00Z\n";
} elsif ($scenario eq 'error') {
  warn "sums server unavailable\n";
  exit 3;
}
exit 0;
FAKE
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $mail_log = "$tmp/mail.log";
open my $mail_fh, '>', "$bin/mailx" or die "Cannot write mailx: $!";
print {$mail_fh} "#!/usr/bin/env perl\nuse v5.38;\n";
print {$mail_fh} 'open my $fh, q{>>}, ', quote($mail_log), ' or die $!;', "\n";
print {$mail_fh} 'print {$fh} join(q{ }, @ARGV), qq{\n}, do { local $/; <STDIN> };', "\n";
print {$mail_fh} 'close $fh;',                                                       "\n";
close $mail_fh or die "Cannot close mailx: $!";
chmod 0755, "$bin/mailx" or die "Cannot chmod mailx: $!";

my $cfg = "$tmp/config.pl";
open my $cfg_fh, '>', $cfg or die "Cannot write $cfg: $!";
print {$cfg_fh} "use v5.38;\nreturn {\n";
print {$cfg_fh} "  tz => 'UTC', sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", quote($show_info), ",\n";
print {$cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$cfg_fh} "  logs_dir => ", quote("$tmp/logs"), ",\n";
print {$cfg_fh} "  mail_to => 'ops1,ops2',\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $cfg: $!";

my $query_log = "$tmp/show_info.log";
local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;
local $ENV{PATH}               = "$bin:$ENV{PATH}";
local $ENV{SHOW_INFO_LOG}      = $query_log;

my $now = timegm( 5, 17, 12, 10, 8, 2026 );    # 2026-09-10T12:17:05Z

sub read_mail {
  return q{} unless -e $mail_log;
  open my $fh, '<', $mail_log or die "Cannot read $mail_log: $!";
  my $text = do { local $/; <$fh> };
  close $fh or die "Cannot close $mail_log: $!";
  return $text;
}

sub run_check {
  my @args   = @_;
  my $output = qx("$^X" "$repo/check_pointing_freshness.pl" -now=$now @args 2>&1);
  return ( $? >> 8, $output );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'fresh';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  is( $exit,   0,   'current table exits successfully' ) or diag $output;
  is( $output, q{}, 'current table is silent' );
  ok( !-e $mail_log, 'current table sends no mail' );

  open my $log_fh, '<', $query_log or die "Cannot read $query_log: $!";
  my $queries = do { local $/; <$log_fh> };
  close $log_fh or die "Cannot close $query_log: $!";
  like( $queries, qr{key=DATE,T_START,T_STOP}, 'query reads the publication and coverage keys' );
  like(
    $queries,
    qr{\Qtest.master_pointing3h[2026.08.10_12:17-2026.09.10_12:17]\E},
    'query spans the grace window and the diagnostic lookback'
  );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'stale';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  isnt( $exit, 0, 'stale table exits unsuccessfully' );
  like(
    $output,
    qr{has not been updated for more than 24 h},
    'diagnostic explains the missing update'
  );
  my $mail = read_mail();
  like(
    $mail,
    qr{-s test[.]master_pointing3h update missing for 47 h ops1 ops2},
    'mailx is called with the subject and both recipients'
  );
  like( $mail, qr{2026-09-08T13:02:11Z \(47[.]2 h ago\)},       'mail reports the newest DATE' );
  like( $mail, qr{Newest record: T_START=2026-09-07T12:00:00Z}, 'mail reports the newest record' );
  like( $mail, qr{check_pointing_gaps[.]pl},                    'mail points at the gap report' );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'stale';
  unlink $mail_log;
  my ( $exit, $output ) = run_check('-grace-hours=48');
  is( $exit, 0, 'a wider grace window accepts the same table' ) or diag $output;
  ok( !-e $mail_log, 'a wider grace window sends no mail' );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'gap';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  isnt( $exit, 0, 'coverage gap exits unsuccessfully' ) or diag $output;
  my $mail = read_mail();
  like( $mail, qr{coverage gaps: 1}, 'subject counts the gaps' );
  like(
    $mail,
    qr{2026-09-05T00:00:00Z -> 2026-09-05T09:00:00Z \(9[.]0 h, 2 missing slots\)},
    'mail reports the gap and its missing slots'
  );
  like(
    $mail,
    qr{check_pointing_gaps[.]pl -year=2026 -month=9 -day=3 -end_year=2026 -end_month=9 -end_day=10},
    'mail gives a runnable gap-report command'
  );
  unlike( $mail, qr{not been updated}, 'a fresh table does not claim a missing update' );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'gap';
  unlink $mail_log;
  my ( $exit, $output ) = run_check('-gap-days=1');
  is( $exit, 0, 'gaps outside the scan window are ignored' ) or diag $output;
  ok( !-e $mail_log, 'gaps outside the scan window send no mail' );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'nodate';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  isnt( $exit, 0, 'unreadable DATE fails the check' );
  like( read_mail(), qr{none carries a readable DATE}, 'unreadable DATE is explained' );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'empty';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  isnt( $exit, 0, 'empty result set fails the check' );
  like(
    read_mail(),
    qr{No test[.]master_pointing3h records were found in the last 30 days},
    'empty result set is explained'
  );
}

{
  local $ENV{SHOW_INFO_SCENARIO} = 'error';
  unlink $mail_log;
  my ( $exit, $output ) = run_check();
  isnt( $exit, 0, 'query failure fails the check' );
  my $mail = read_mail();
  like( $mail, qr{freshness check failed}, 'query failure is reported as a check failure' );
  like( $mail, qr{show_info failed},       'mail includes the DRMS error' );
}

done_testing;
