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
my $drms = "$tmp/drms";
make_path(
  "$drms/bin/linux_avx2",
  "$drms/lib/linux_avx2",
  "$drms/include/base",
  "$drms/scripts",
  "$drms/src",
);

my $show_info = "$drms/bin/linux_avx2/show_info";
open my $show_fh, '>', $show_info or die "Cannot write $show_info: $!";
print {$show_fh} "#!/usr/bin/env perl\n";
print {$show_fh} "use strict;\nuse warnings;\n";
print {$show_fh} "print qq{2026-05-01T00:00:00Z 2026-05-01T03:00:00Z 10 20\\n};\n";
print {$show_fh} "print qq{2026-05-01T03:00:00Z 2026-05-01T04:30:00Z 11 21\\n};\n";
print {$show_fh} "print qq{2026-05-01T04:30:00Z 2026-05-01T04:30:00Z 12 22\\n};\n";
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  wl => [94],\n";
print {$cfg_fh} "  tz => 'UTC',\n";
print {$cfg_fh} "  sumserver => 'test',\n";
print {$cfg_fh} "  show_info => ", perl_quote($show_info), ",\n";
print {$cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$cfg_fh} "  cadence_h => 3,\n";
print {$cfg_fh} "  nan_sentinel => 1234567,\n";
print {$cfg_fh} "  fits_root => ", perl_quote("$tmp/fits"), ",\n";
print {$cfg_fh} "  check_gaps_dir => ", perl_quote("$tmp/check"), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;
my $output = qx("$^X" "$repo/check_pointing_gaps.pl" -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
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
unlike( $output, qr{run_limbfit_ymdh[.]pl}, 'invalid records alone do not trigger backfill commands' );
ok( -e "$tmp/check/patch.txt", 'patch file is created in check directory' );

done_testing;
