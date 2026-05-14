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
      lf_sed     => '/tmp/lf.sed',
      perl       => '/usr/bin/perl',
      lf2mpr     => '/repo/lf2mpr_nrt.pdl',
      update3h   => '/repo/update3h_mpt.pl',
    )
  ],
  [
    [ 'sed', '-i', '-f', '/tmp/lf.sed', '/tmp/fits/2026/05/01/20260501_03_0171.limb' ],
    [
      '/usr/bin/perl', '/repo/lf2mpr_nrt.pdl', '-inpdir', '/tmp/fits', '-outdir', '/tmp/update',
      '-y', 2026, '-mo', 5, '-da', 1, '-h', 3,
    ],
    [ '/usr/bin/perl', '/repo/update3h_mpt.pl', '-src', '/tmp/update', '-ser', 'aia.master_pointing3h' ],
  ],
  'patch command arguments'
);

done_testing;
