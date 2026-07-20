use v5.38;
use FindBin     qw($Bin);
use File::Path  qw(make_path);
use File::Temp  qw(tempdir);
use Time::Local qw(timegm);
use lib "$Bin/../lib";
use Test::More;

use AIALimbfit::Inventory qw(expected_limb_path missing_limb_paths);

is(
  expected_limb_path( '/tmp/fits', 2026, 5, 1, 3, 94 ),
  '/tmp/fits/2026/05/01/20260501_03_0094.limb',
  'expected limb path'
);

my $tmp = tempdir( CLEANUP => 1 );
make_path("$tmp/2026/05/01");
open my $fh, '>', "$tmp/2026/05/01/20260501_00_0094.limb" or die "Cannot write fixture: $!";
print {$fh} "fixture\n";
close $fh or die "Cannot close fixture: $!";
open my $empty_fh, '>', "$tmp/2026/05/01/20260501_00_0171.limb"
  or die "Cannot write empty fixture: $!";
close $empty_fh or die "Cannot close empty fixture: $!";

my @missing = missing_limb_paths(
  fits_root   => $tmp,
  wavelengths => [ 94, 171 ],
  cadence_h   => 3,
  year        => 2026,
  month       => 5,
  day         => 1,
  end_epoch   => timegm( 0, 0, 6, 1, 4, 2026 ),
);

is_deeply(
  \@missing,
  [
    "$tmp/2026/05/01/20260501_00_0171.limb", "$tmp/2026/05/01/20260501_03_0094.limb",
    "$tmp/2026/05/01/20260501_03_0171.limb",
  ],
  'missing inventory treats only non-empty files as present'
);

@missing = missing_limb_paths(
  fits_root   => $tmp,
  wavelengths => [94],
  cadence_h   => 3,
  year        => 2026,
  month       => 5,
  day         => 1,
  now_epoch   => timegm( 0, 0, 3, 2, 4, 2026 ),
  buffer_s    => 10_800,
);
is_deeply(
  \@missing,
  [
    "$tmp/2026/05/01/20260501_03_0094.limb", "$tmp/2026/05/01/20260501_06_0094.limb",
    "$tmp/2026/05/01/20260501_09_0094.limb", "$tmp/2026/05/01/20260501_12_0094.limb",
    "$tmp/2026/05/01/20260501_15_0094.limb", "$tmp/2026/05/01/20260501_18_0094.limb",
    "$tmp/2026/05/01/20260501_21_0094.limb",
  ],
  'now_epoch plus buffer chooses end time'
);

@missing = missing_limb_paths(
  fits_root   => $tmp,
  wavelengths => [94],
  cadence_h   => 3,
  year        => 2026,
  month       => 5,
  day         => 1,
  end_epoch   => timegm( 0, 0, 0, 1, 4, 2026 ),
);
is( scalar @missing, 0, 'start equal to end_epoch returns empty list' );

@missing = missing_limb_paths(
  fits_root   => $tmp,
  wavelengths => [94],
  cadence_h   => 3,
  year        => 2026,
  month       => 5,
  day         => 1,
  end_epoch   => timegm( 0, 0, 3, 1, 4, 2026 ),
);
is( scalar( grep { /20260501_03_0094/ } @missing ), 0, 'slot at end_epoch boundary is excluded' );

@missing = missing_limb_paths(
  fits_root   => $tmp,
  wavelengths => [94],
  cadence_h   => 3,
  year        => 2026,
  month       => 5,
  day         => 1,
  end_epoch   => timegm( 0, 0, 6, 1, 4, 2026 ),
);
is( scalar( grep { /20260501_03_0094/ } @missing ), 1, 'slot before end_epoch boundary is included' );
is( scalar( grep { /20260501_06_0094/ } @missing ), 0, 'slot at end_epoch is excluded' );

done_testing;
