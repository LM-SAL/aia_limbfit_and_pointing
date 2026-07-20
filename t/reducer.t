use v5.38;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;
use PDL;
use PDL::IO::Misc;

use AIALimbfit::Reducer qw(
  detect_split_cluster
  filter_4500_sentinel
  kwd_lines
  limb_input_path
  masterpoint_filename
  reduce_limb_points
);

my %cfg = (
  nan_sentinel                  => 1_234_567,
  split_cluster_mode            => 'fail',
  split_cluster_min_segment_size => 4,
  split_cluster_jump_sigma      => 6,
  split_cluster_jump_ratio      => 3,
  split_cluster_separation_ratio => 10,
);

is(
  masterpoint_filename( 2026, 5, 1, 0, 3 ),
  'masterpoint_20260501_0130_3hcadence.txt',
  'masterpoint filename uses slot center'
);
is(
  limb_input_path( '/tmp/limb', 2026, 5, 1, 0, 94 ),
  '/tmp/limb/2026/05/01/20260501_00_0094.limb',
  'limb input path uses slot start hour'
);

my ( $x, $y ) = filter_4500_sentinel(
  pdl( 10, 1_234_567, 30 ),
  pdl( 20, 40,        1_234_567 ),
  1_234_567
);
is_deeply( [ list $x ], [10], '4500 sentinel filter removes bad x rows' );
is_deeply( [ list $y ], [20], '4500 sentinel filter removes bad y rows' );

my ( undef, undef, $xavg, $yavg ) = reduce_limb_points(
  pdl( 10, 1_234_567 ),
  pdl( 20, 1_234_567 ),
  4500,
  \%cfg
);
is( $xavg, 10, '4500 reduction filters sentinel before averaging x' );
is( $yavg, 20, '4500 reduction filters sentinel before averaging y' );

( undef, undef, $xavg, $yavg ) = reduce_limb_points(
  pdl( 1, 1, 1 ),
  pdl( 2, 2, 2 ),
  171,
  \%cfg
);
is( $xavg, 1, 'zero-scatter non-4500 keeps finite x average' );
is( $yavg, 2, 'zero-scatter non-4500 keeps finite y average' );

ok(
  !detect_split_cluster( pdl( 0 .. 9 ), pdl( (0) x 10 ), \%cfg ),
  'compact cluster is not split'
);
ok(
  !detect_split_cluster(
    pdl( 0, 1, 2, 100, 101, 102 ),
    pdl( 0, 0, 0, 0,   0,   0 ),
    \%cfg
  ),
  'segments below minimum size are not split'
);
ok(
  detect_split_cluster(
    pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
    pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
    \%cfg
  ),
  'large separated clusters are split'
);

my %ignore_cfg = ( %cfg, split_cluster_mode => 'ignore' );
ok(
  !detect_split_cluster(
    pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
    pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
    \%ignore_cfg
  ),
  'ignore mode disables split-cluster detection'
);

is_deeply(
  [ kwd_lines( 171, 1.25, -2.5 ) ],
  [ "KWD A_171_X0\t1.250000\n", "KWD A_171_Y0\t-2.500000\n\n" ],
  'KWD output lines'
);

( undef, undef, $xavg, $yavg ) = reduce_limb_points(
  pdl( 10, 20 ),
  pdl( 5, 15 ),
  171,
  \%cfg
);
is( $xavg, 15, 'two-point non-4500 bypasses sigma-clip: x average' );
is( $yavg, 10, 'two-point non-4500 bypasses sigma-clip: y average' );

( undef, undef, $xavg, $yavg ) = reduce_limb_points(
  pdl( 1_234_567, 1_234_567 ),
  pdl( 1_234_567, 1_234_567 ),
  4500,
  \%cfg
);
ok( $xavg != $xavg, '4500 all-sentinel -> NaN x average' );
ok( $yavg != $yavg, '4500 all-sentinel -> NaN y average' );

my %clip_all_cfg = ( %cfg, sigma_clip_pass1_sigma => 0 );
eval { reduce_limb_points(
  pdl( 0, 1, 3 ),
  pdl( 0, 0, 0 ),
  171,
  \%clip_all_cfg
) };
like( $@, qr{All 3 limb-fit points rejected by pass 1},
  'pass1 rejection fails explicitly instead of returning NaN' );

my ( $bimodal_x, $bimodal_y ) = rcols( "$Bin/../data/20260707_03_0335.limb", 0, 1 );
eval { reduce_limb_points( $bimodal_x, $bimodal_y, 335, \%cfg ) };
like( $@, qr{All 180 limb-fit points rejected by pass 1.*multimodal},
  'bimodal real data fails explicitly instead of returning NaN' );

ok(
  !detect_split_cluster(
    pdl( 0, 0, 100 ),
    pdl( 0, 0, 100 ),
    \%cfg
  ),
  'three-point input (2 jumps) returns early from split detection'
);

done_testing;
