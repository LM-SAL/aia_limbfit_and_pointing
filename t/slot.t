use v5.42;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use AIALimbfit::Slot qw(
  drms_time
  parse_masterpoint_filename
  series_contains_time_query
  slot_bounds_from_masterpoint
  slot_record_issues
  slot_sequence_issues
);

sub issues_string {
  return join ',', sort @_;
}

my $parts = parse_masterpoint_filename('masterpoint_20260501_0130_3hcadence.txt');
is_deeply(
  $parts,
  {
    year       => 2026,
    month      => 5,
    day        => 1,
    hour       => 1,
    minute     => 30,
    duration_h => 3,
  },
  'parse masterpoint filename'
);

ok(
  !defined parse_masterpoint_filename('masterpoint_20260501_0130.txt'),
  'reject missing cadence filename'
);
ok(
  !defined parse_masterpoint_filename('not_masterpoint_20260501_0130_3hcadence.txt'),
  'reject wrong prefix filename'
);

my $slot = slot_bounds_from_masterpoint('masterpoint_20260501_0130_3hcadence.txt');
is( $slot->{t_start}, '2026-05-01T00:00:00Z', 'center filename maps to slot start' );
is( $slot->{t_stop},  '2026-05-01T03:00:00Z', 'center filename maps to slot stop' );

$slot = slot_bounds_from_masterpoint('masterpoint_20260501_0430_3hcadence.txt');
is( $slot->{t_start}, '2026-05-01T03:00:00Z', 'next center maps to next slot start' );
is( $slot->{t_stop},  '2026-05-01T06:00:00Z', 'next center maps to next slot stop' );

$slot = slot_bounds_from_masterpoint('masterpoint_20260501_0030_1hcadence.txt');
is( $slot->{t_start}, '2026-05-01T00:00:00Z', '1h slot maps from center to start' );
is( $slot->{t_stop},  '2026-05-01T01:00:00Z', '1h slot maps from center to stop' );

is( drms_time('2026-05-01T00:00:00Z'), '$(2026-05-01T00:00:00Z)', 'format DRMS time literal' );
is(
  series_contains_time_query( 'aia.master_pointing3h', '2026-05-01T00:00:00Z' ),
  'aia.master_pointing3h[?T_START<=$(2026-05-01T00:00:00Z) and $(2026-05-01T00:00:00Z)<T_STOP?]',
  'format contains-time query'
);

is(
  issues_string( slot_record_issues(
    {
      t_start => '2026-05-01T00:00:00Z',
      t_stop  => '2026-05-01T03:00:00Z',
    },
    cadence_s => 10_800
  ) ),
  q{},
  'valid 3h slot has no issues'
);

is(
  issues_string( slot_record_issues(
    {
      t_start => '2026-05-01T01:30:00Z',
      t_stop  => '2026-05-01T03:00:00Z',
    },
    cadence_s => 10_800
  ) ),
  'off_grid_start,wrong_duration',
  '90-minute off-grid record is invalid'
);

is(
  issues_string( slot_record_issues(
    {
      t_start => '2026-05-01T01:30:00Z',
      t_stop  => '2026-05-01T01:30:00Z',
    },
    cadence_s => 10_800
  ) ),
  'non_positive_duration,off_grid_start,off_grid_stop',
  'same-start-stop off-grid record is invalid'
);

my @issues = slot_sequence_issues(
  [
    {
      t_start => '2026-05-01T00:00:00Z',
      t_stop  => '2026-05-01T03:00:00Z',
    },
    {
      t_start => '2026-05-01T03:00:00Z',
      t_stop  => '2026-05-01T06:00:00Z',
    },
  ],
  cadence_s => 10_800
);
is( scalar( grep { $_->{type} eq 'gap' || $_->{type} eq 'overlap' } @issues ), 0, 'contiguous records have no gap or overlap' );

@issues = slot_sequence_issues(
  [
    {
      t_start => '2026-05-01T00:00:00Z',
      t_stop  => '2026-05-01T03:00:00Z',
    },
    {
      t_start => '2026-05-01T06:00:00Z',
      t_stop  => '2026-05-01T09:00:00Z',
    },
  ],
  cadence_s => 10_800
);
is( scalar( grep { $_->{type} eq 'gap' } @issues ), 1, 'missing slot is reported as a gap' );

@issues = slot_sequence_issues(
  [
    {
      t_start => '2026-05-01T00:00:00Z',
      t_stop  => '2026-05-01T03:00:00Z',
    },
    {
      t_start => '2026-05-01T01:30:00Z',
      t_stop  => '2026-05-01T04:30:00Z',
    },
  ],
  cadence_s => 10_800
);
is( scalar( grep { $_->{type} eq 'overlap' } @issues ), 1, 'overlapping records are reported' );

done_testing;
