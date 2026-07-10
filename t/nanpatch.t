use v5.42;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use AIALimbfit::NanPatch qw(limb_path parse_patch_line patch_commands);

my $entry = parse_patch_line('2026-05-01T03:00:00Z 171 NaN NaN');
is_deeply(
  $entry,
  {
    datetime   => '2026-05-01T03:00:00Z',
    wavelength => 171,
    x_center   => 'NaN',
    y_center   => 'NaN',
    year       => 2026,
    month      => 5,
    day        => 1,
    hour       => 3,
    minute     => 0,
    second     => 0,
  },
  'parse patch input line'
);

ok( !defined parse_patch_line('not a patch line'), 'reject malformed patch line' );
ok(
  !defined parse_patch_line('2026-05-01T03:00:00Z abc NaN NaN'),
  'reject nonnumeric wavelength'
);

my $missing_entry = parse_patch_line('2026-05-01T03:00:00Z 171 MISSING MISSING');
ok( defined $missing_entry, 'MISSING keyword accepted in patch line' );
is( $missing_entry->{x_center}, 'MISSING', 'MISSING value preserved as x_center' );

my $lc_missing = parse_patch_line('2026-05-01T03:00:00Z 171 missing missing');
ok( defined $lc_missing, 'lowercase missing accepted in patch line' );

my $neg_entry = parse_patch_line('2026-05-01T03:00:00Z 171 -123.4 456.7');
ok( defined $neg_entry, 'negative coordinate accepted in patch line' );
is( $neg_entry->{x_center}, '-123.4', 'negative x_center preserved' );
is( $neg_entry->{y_center}, '456.7',  'positive y_center preserved' );

my $sci_entry = parse_patch_line('2026-05-01T03:00:00Z 171 1.5e+02 -2.3e-01');
ok( defined $sci_entry, 'scientific notation accepted in patch line' );
is( $sci_entry->{x_center}, '1.5e+02', 'scientific notation x_center preserved' );

ok( !defined parse_patch_line('2026-05-01T03:00:00 171 NaN NaN'), 'missing Z rejected' );
ok( !defined parse_patch_line(''),                                  'empty string rejected' );
ok( !defined parse_patch_line("   \n"),                             'whitespace-only line rejected' );

is(
  limb_path( '/tmp/fits', $entry ),
  '/tmp/fits/2026/05/01/20260501_03_0171.limb',
  'patch target limb path'
);

is_deeply(
  [ patch_commands(
      $entry,
      fits_root  => '/tmp/fits',
      update_dir => '/tmp/update',
      series     => 'aia.master_pointing3h',
      perl       => '/usr/bin/perl',
      lf2mpr     => '/repo/lf2mpr_nrt.pdl',
      update3h   => '/repo/update3h_mpt.pl',
    )
  ],
  [
    [
      '/usr/bin/perl', '/repo/lf2mpr_nrt.pdl', '-inpdir', '/tmp/fits', '-outdir', '/tmp/update',
      '-y', 2026, '-mo', 5, '-da', 1, '-h', 3, '-require-all',
    ],
    [ '/usr/bin/perl', '/repo/update3h_mpt.pl', '-src', '/tmp/update', '-ser', 'aia.master_pointing3h' ],
  ],
  'repair command arguments do not depend on an external sed script'
);

done_testing;
