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
like( $output, qr{TEMPORAL GAP\s+2026-05-01T03:00:00Z\s+->\s+2026-05-02T00:00:00Z},
  'gap detection includes the requested range boundary' );
ok( !-e "$tmp/check", 'report-only mode creates no repair files' );

my $repair_tmp = tempdir( CLEANUP => 1 );
my $repair_drms = "$repair_tmp/drms";
make_path(
  "$repair_drms/bin/linux_avx2",
  "$repair_drms/lib/linux_avx2",
  "$repair_drms/include/base",
  "$repair_drms/scripts",
  "$repair_drms/src",
);

my $repair_show = "$repair_drms/bin/linux_avx2/show_info";
open my $repair_show_fh, '>', $repair_show or die "Cannot write $repair_show: $!";
print {$repair_show_fh} <<'PERL';
#!/usr/bin/env perl
use strict;
use warnings;
for my $hour ( 0, 3, 6, 9, 12, 15, 18, 21 ) {
  my $start = sprintf '2026-05-01T%02d:00:00Z', $hour;
  my $stop = $hour == 21 ? '2026-05-02T00:00:00Z' : sprintf '2026-05-01T%02d:00:00Z', $hour + 3;
  my $xy = $hour == 3 ? 'NaN NaN' : '10 20';
  print "$start $stop $xy\n";
}
PERL
close $repair_show_fh or die "Cannot close $repair_show: $!";
chmod 0755, $repair_show or die "Cannot chmod $repair_show: $!";

my $fake_limbfit = "$repair_tmp/limbfit";
open my $limbfit_fh, '>', $fake_limbfit or die "Cannot write $fake_limbfit: $!";
print {$limbfit_fh} <<'PERL';
#!/usr/bin/env perl
use strict;
use warnings;
print "10 20 30 0 2026-05-01T03:00:00Z 30\n" for 1 .. 3;
PERL
close $limbfit_fh or die "Cannot close $fake_limbfit: $!";
chmod 0755, $fake_limbfit or die "Cannot chmod $fake_limbfit: $!";

my $repair_config = "$repair_tmp/config.pl";
open my $repair_cfg_fh, '>', $repair_config or die "Cannot write $repair_config: $!";
print {$repair_cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$repair_cfg_fh} "  wl => [94],\n";
print {$repair_cfg_fh} "  tz => 'UTC',\n";
print {$repair_cfg_fh} "  sumserver => 'test',\n";
print {$repair_cfg_fh} "  sge_root => '/SGE',\n";
print {$repair_cfg_fh} "  drms_root_dir => ", perl_quote($repair_drms), ",\n";
print {$repair_cfg_fh} "  drms_params_install_dir => ", perl_quote("$repair_drms/include/base"), ",\n";
print {$repair_cfg_fh} "  drms_scrs_install_dir => ", perl_quote("$repair_drms/scripts"), ",\n";
print {$repair_cfg_fh} "  drms_src_install_dir => ", perl_quote("$repair_drms/src"), ",\n";
print {$repair_cfg_fh} "  show_info => ", perl_quote($repair_show), ",\n";
print {$repair_cfg_fh} "  limbfit_exe => ", perl_quote($fake_limbfit), ",\n";
print {$repair_cfg_fh} "  drms_filter => '[?MISSVALS<99?]',\n";
print {$repair_cfg_fh} "  mpt_series => 'test.master_pointing3h',\n";
print {$repair_cfg_fh} "  cadence_h => 3,\n";
print {$repair_cfg_fh} "  nan_sentinel => 1234567,\n";
print {$repair_cfg_fh} "  split_cluster_mode => 'ignore',\n";
print {$repair_cfg_fh} "  fits_root => ", perl_quote("$repair_tmp/fits"), ",\n";
print {$repair_cfg_fh} "  test_fits_root => ", perl_quote("$repair_tmp/test"), ",\n";
print {$repair_cfg_fh} "  pointing_dir => ", perl_quote("$repair_tmp/pointing"), ",\n";
print {$repair_cfg_fh} "  check_gaps_dir => ", perl_quote("$repair_tmp/check"), ",\n";
print {$repair_cfg_fh} "};\n";
close $repair_cfg_fh or die "Cannot close $repair_config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $repair_config;
$output = qx("$^X" "$repo/check_pointing_gaps.pl" -repair -year=2026 -month=5 -day=1 -end_year=2026 -end_month=5 -end_day=1 2>&1);
is( $? >> 8, 0, 'repair mode exits successfully' ) or diag $output;
ok( -s "$repair_tmp/fits/2026/05/01/20260501_03_0094.limb",
  'regenerated wavelength is installed in the production limb tree' );
ok( -s "$repair_tmp/check/stage/masterpoint_20260501_0430_3hcadence.txt",
  'repair mode stages a complete masterpoint file' );
like( $output, qr{update3h_mpt[.]pl -dry-run}, 'repair mode prints a DRMS preview command' );

done_testing;
