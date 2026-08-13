use v5.38;
use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

sub write_config ( $path, %values ) {
  open my $fh, '>', $path or die "Cannot write $path: $!";
  print {$fh} "use v5.38;\nreturn {\n";
  print {$fh} "  wl => [", join( ',', @{ $values{wl} // [ 94, 171, 4500 ] } ), "],\n";
  print {$fh} "  cadence_h => 3, sumserver => 'test', sge_root => '/SGE', tz => 'UTC',\n";
  print {$fh} "  drms_root_dir => '/drms', drms_params_install_dir => '/drms/include/base',\n";
  print {$fh} "  drms_scrs_install_dir => '/drms/scripts', drms_src_install_dir => '/drms/src',\n";
  print {$fh} "  drms_filter => '[?MISSVALS<99?]', lev1_series => 'aia.lev1_nrt2',\n";
  for my $key (qw(fits_root check_gaps_dir logs_dir pointing_dir limbfit_exe mail_to)) {
    print {$fh} "  $key => ", quote( $values{$key} ), ",\n" if defined $values{$key};
  }
  print {$fh} "};\n";
  close $fh or die "Cannot close $path: $!";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $cfg  = "$tmp/config.pl";
write_config(
  $cfg,
  fits_root     => "$tmp/fits",
  check_gaps_dir => "$tmp/gaps",
  logs_dir      => "$tmp/logs",
  pointing_dir  => "$tmp/stage",
  limbfit_exe   => '/bin/limbfit',
);
local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;

my $output = qx("$^X" "$repo/run_limbfit_ymdh.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'all-wavelength dry run succeeds' ) or diag $output;
like( $output, qr{aia[.]lev1_nrt2\[2026[.]05[.]01_03/3h\].*WAVELNTH=94}, 'query is fixed at 3h' );
like( $output, qr{20260501_03_4500[.]limb}, 'all configured wavelengths are printed' );
unlike( $output, qr{plot_limb[.]py}, 'production run does not plot' );

$output = qx("$^X" "$repo/run_limbfit_ymdh.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 -wavel=171 2>&1);
is( $? >> 8, 0, 'single-wavelength dry run succeeds' ) or diag $output;
like( $output, qr{\Q$tmp/gaps/limb/2026/05/01/20260501_03_0171.limb\E},
  'diagnostic run defaults to the backfill workspace' );
like( $output, qr{plot_limb[.]py}, 'diagnostic run plots by default' );

$output = qx("$^X" "$repo/run_limbfit_ymdh.pl" -dry-run -dur=6h -year=2026 -month=5 -day=1 -hour=3 2>&1);
isnt( $? >> 8, 0, 'duration override was removed' );

$output = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=3 2>&1);
is( $? >> 8, 0, 'cron dry run succeeds' ) or diag $output;
like( $output, qr{run_limbfit_ymdh[.]pl.*-hour=3}, 'cron prints limb-fit step' );
like( $output, qr{lf2mpr_nrt[.]pdl.*-outdir=\Q$tmp/stage/20260501_03\E}, 'cron prints reducer step' );
like( $output, qr{update3h_mpt[.]pl.*-delete}, 'cron prints publish step' );

$output = qx("$^X" "$repo/cron_submit_slot.pl" -dry-run -year=2026 -month=5 -day=1 -hour=4 2>&1);
isnt( $? >> 8, 0, 'off-grid cron slot is rejected' );
like( $output, qr{Hour must be on the three-hour grid}, 'off-grid error is explicit' );

my $mixed = "$tmp/mixed_limbfit.pl";
open my $mixed_fh, '>', $mixed or die "Cannot write $mixed: $!";
print {$mixed_fh} <<'FAKE';
#!/usr/bin/env perl
use v5.38;
my $args = join q{ }, @ARGV;
exit 3 if $args =~ /WAVELNTH=94/;
print "1 2 3 4 time 3\n";
FAKE
close $mixed_fh or die "Cannot close $mixed: $!";
chmod 0755, $mixed or die "Cannot chmod $mixed: $!";
my $mixed_cfg = "$tmp/mixed.pl";
write_config(
  $mixed_cfg,
  wl             => [ 94, 171 ],
  fits_root      => "$tmp/mixed_fits",
  check_gaps_dir => "$tmp/gaps",
  limbfit_exe    => $mixed,
);
local $ENV{AIA_LIMBFIT_CONFIG} = $mixed_cfg;
$output = qx("$^X" "$repo/run_limbfit_ymdh.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
isnt( $? >> 8, 0, 'one failed wavelength fails the slot' );
like( $output, qr{failed=94A}, 'failed wavelength is summarized' );
ok( !-e "$tmp/mixed_fits/2026/05/01/20260501_03_0094.limb", 'failed output is removed' );
ok( -s "$tmp/mixed_fits/2026/05/01/20260501_03_0171.limb", 'successful sibling remains diagnosable' );

my $failed = "$tmp/failed_limbfit.pl";
open my $failed_fh, '>', $failed or die "Cannot write $failed: $!";
print {$failed_fh} "#!/usr/bin/env perl\nuse v5.38;\nwarn qq{limbfit-boom-detail\\n};\nexit 7;\n";
close $failed_fh or die "Cannot close $failed: $!";
chmod 0755, $failed or die "Cannot chmod $failed: $!";
my $fake_bin = "$tmp/bin";
make_path($fake_bin);
my $mail_log = "$tmp/mail.log";
open my $mail_fh, '>', "$fake_bin/mailx" or die "Cannot write mailx: $!";
print {$mail_fh} "#!/usr/bin/env perl\nuse v5.38;\n";
print {$mail_fh} 'open my $fh, q{>>}, ', quote($mail_log), ' or die $!;', "\n";
print {$mail_fh} 'print {$fh} join(q{ }, @ARGV), qq{\n}, do { local $/; <STDIN> };', "\n";
print {$mail_fh} 'close $fh;', "\n";
close $mail_fh or die "Cannot close mailx: $!";
chmod 0755, "$fake_bin/mailx" or die "Cannot chmod mailx: $!";
my $fail_cfg = "$tmp/fail.pl";
write_config(
  $fail_cfg,
  wl             => [94],
  fits_root      => "$tmp/fail_fits",
  check_gaps_dir => "$tmp/gaps",
  logs_dir       => "$tmp/logs",
  pointing_dir   => "$tmp/stage",
  limbfit_exe    => $failed,
  mail_to        => 'ops1,ops2',
);
{
  local $ENV{AIA_LIMBFIT_CONFIG} = $fail_cfg;
  local $ENV{PATH} = "$fake_bin:$ENV{PATH}";
  $output = qx("$^X" "$repo/cron_submit_slot.pl" -year=2026 -month=5 -day=1 -hour=3 2>&1);
}
isnt( $? >> 8, 0, 'cron propagates pipeline failure' );
like( $output, qr{failed .* at limbfit: exit 1}, 'cron names the failed step and exit code' );
ok( -s $mail_log, 'cron sends one failure email' );
open my $read_mail, '<', $mail_log or die "Cannot read $mail_log: $!";
my $mail = do { local $/; <$read_mail> };
close $read_mail;
like( $mail, qr{limbfit-boom-detail}, 'email includes the useful log tail' );

done_testing;
