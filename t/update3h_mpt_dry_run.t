use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path);
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
use strict;
use warnings;

if ($ENV{SHOW_INFO_LOG}) {
  open my $log_fh, '>>', $ENV{SHOW_INFO_LOG} or die "Cannot write SHOW_INFO_LOG: $!";
  print {$log_fh} join("\t", @ARGV), "\n";
  close $log_fh or die "Cannot close SHOW_INFO_LOG: $!";
}

my $query = join q{ }, @ARGV;
if ($query =~ /sdo[.]master_pointing/) {
  print "T_START\tT_STOP\tDATE\tVERSION\tSAT_ROT\n";
  print "2026-05-01T00:00:00Z\t2026-05-01T03:00:00Z\t2026-05-01T00:00:00Z\t0\t42\n";
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
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$cfg_fh} "  set_info => ",  perl_quote($set_info),  ",\n";
print {$cfg_fh} "  mpt_series => 'test.series',\n";
print {$cfg_fh} "  sdo_series => 'sdo.master_pointing',\n";
print {$cfg_fh} "  pointing_dir => ", perl_quote($stage), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

my $query_log = "$tmp/show_info.log";
local $ENV{AIA_LIMBFIT_CONFIG} = $config;
local $ENV{SHOW_INFO_LOG}      = $query_log;

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

done_testing;
