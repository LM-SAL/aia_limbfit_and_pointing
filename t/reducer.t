use v5.38;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use AIALimbfit::Inventory qw(limb_path);
use AIALimbfit::Reducer qw(detect_split_cluster kwd_lines masterpoint_filename reduce_limb_points);
use PDL;
use PDL::IO::Misc;
use Test::More;

my %cfg = (
  nan_sentinel                   => 1_234_567,
  sigma_clip_pass1_sigma         => 2,
  sigma_clip_pass2_sigma         => 3,
  split_cluster_min_segment_size => 4,
  split_cluster_separation_ratio => 10,
);

is(
  masterpoint_filename( 2026, 5, 1, 0, 3 ),
  'masterpoint_20260501_0130_3hcadence.txt',
  'masterpoint filename uses slot center'
);
is(
  limb_path( '/tmp/limb', 2026, 5, 1, 0, 94 ),
  '/tmp/limb/2026/05/01/20260501_00_0094.limb',
  'canonical limb path is padded'
);

my ( undef, undef, $xavg, $yavg ) = reduce_limb_points(
  pdl( 10, 1_234_567 ),
  pdl( 20, 1_234_567 ),
  4500,
  \%cfg
);
is( $xavg, 10, '4500 reduction filters sentinel x' );
is( $yavg, 20, '4500 reduction filters sentinel y' );

( undef, undef, $xavg, $yavg ) = reduce_limb_points( pdl( (10) x 6 ), pdl( (20) x 6 ), 171, \%cfg );
is( $xavg, 10, 'ordinary reduction retains finite x values' );
is( $yavg, 20, 'ordinary reduction retains finite y values' );

ok( !detect_split_cluster( pdl( 0 .. 9 ), pdl( (0) x 10 ), \%cfg ), 'compact data is not split' );
ok(
  !detect_split_cluster( pdl( 0, 1, 2, 100, 101, 102 ), pdl( (0) x 6 ), \%cfg ),
  'segments below the minimum are not split'
);
my $split = detect_split_cluster(
  pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
  pdl( 0, 0.1, -0.1, 0.2, 100, 100.1, 99.9, 100.2 ),
  \%cfg
);
is( $split->{split_after}, 4, 'split location is reported' );
is_deeply( [ @{$split}{qw(first_segment second_segment)} ], [ 4, 4 ], 'segment sizes are reported' );

is_deeply(
  [ kwd_lines( 171, 1.25, -2.5 ) ],
  [ "KWD A_171_X0\t1.250000\n", "KWD A_171_Y0\t-2.500000\n\n" ],
  'masterpoint keyword format'
);

my ( $split_x, $split_y ) = rcols( "$Bin/../data/20260326_18_0094.limb", 0, 1 );
eval { reduce_limb_points( $split_x, $split_y, 94, \%cfg ) };
like(
  $@,
  qr{Split-cluster detected \(94A\): split after row 88, segments 88/92},
  'real split failure tells the operator where to cut'
);

my ( $bimodal_x, $bimodal_y ) = rcols( "$Bin/../data/20260707_03_0335.limb", 0, 1 );
eval { reduce_limb_points( $bimodal_x, $bimodal_y, 335, \%cfg ) };
like( $@, qr{All 180 limb-fit points rejected by pass 1.*multimodal}, 'other multimodal data fails clearly' );

done_testing;
