use v5.38;
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
print {$show_fh} <<'SCRIPT';
#!/usr/bin/env perl
use v5.38;
if ($ENV{SHOW_INFO_LOG}) {
  open my $log_fh, '>>', $ENV{SHOW_INFO_LOG} or die "Cannot write SHOW_INFO_LOG: $!";
  print {$log_fh} join("\t", @ARGV), "\n";
  close $log_fh or die "Cannot close SHOW_INFO_LOG: $!";
}
if (($ENV{SHOW_INFO_SCENARIO} // 'invalid') eq 'valid') {
  print "1 2026-03-26T17:00:00Z 94 1603.3 2055.5 2048.5 0 0\n";
}
else {
  print "1 2026-03-26T17:00:00Z 94 1603.3 2055.5 2048.5 0 0\n";
  print "2 2026-03-26T18:00:00Z 94 1603.3 nan nan nan 0\n";
  print "3 2026-03-26T18:00:00Z 304 0 2055.5 -1 0 -12.4\n";
  print "4 2026-03-26T18:00:00Z 171 1603.3 2055.5 2048.5 nan 0\n";
}
SCRIPT
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use v5.38;\nreturn {\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;
my $query_log = "$tmp/show_info.log";
local $ENV{SHOW_INFO_LOG}      = $query_log;
local $ENV{SHOW_INFO_SCENARIO} = 'invalid';
my $output = qx("$^X" "$repo/scan_lev1_geometry.pl" -ds='aia.lev1[test]' 2>&1);
is( $? >> 8, 1, 'invalid geometry produces a non-zero status' ) or diag $output;
like( $output, qr{FSN=2 .* fields=CRPIX1,CRPIX2,CRVAL1}, 'NaN image-center values are reported' );
like( $output, qr{FSN=3 .* fields=R_SUN,CRPIX2\b},       'zero and negative values are reported' );
like( $output, qr{FSN=4 .* fields=CRVAL1\b}, 'NaN CRVAL is reported while zero CRVAL is accepted' );
like( $output, qr{SUMMARY records=4 invalid=3}, 'invalid scan summary is correct' );

open my $log_fh, '<', $query_log or die "Cannot read $query_log: $!";
my $query = <$log_fh>;
close $log_fh or die "Cannot close $query_log: $!";
like(
  $query,
  qr{key=FSN,T_OBS,WAVELNTH,R_SUN,CRPIX1,CRPIX2,CRVAL1,CRVAL2\b},
  'scanner requests the geometry keywords',
);

local $ENV{SHOW_INFO_SCENARIO} = 'valid';
$output = qx("$^X" "$repo/scan_lev1_geometry.pl" -ds='aia.lev1[test]' 2>&1);
is( $? >> 8, 0, 'valid geometry exits successfully' ) or diag $output;
like( $output, qr{SUMMARY records=1 invalid=0}, 'valid scan summary is correct' );

done_testing;
