use strict;
use warnings;
use FindBin qw($Bin);
use Time::Local qw(timegm);
use lib "$Bin/../lib";
use Test::More;

use AIALimbfit::CronSlot qw(default_slot_from_epoch pipeline_call pipeline_shell_command run_id should_run_hour);

is_deeply(
  [ default_slot_from_epoch( timegm( 0, 0, 0, 2, 4, 2026 ), 3600 ) ],
  [ 2026, 5, 1, 23 ],
  'default slot handles day rollover'
);

ok( should_run_hour(0),  '00 UTC should run' );
ok( should_run_hour(21), '21 UTC should run' );
ok( !should_run_hour(22), '22 UTC should skip' );

is( run_id( 2026, 5, 1, 3 ), '20260501_03', 'run id format' );
is(
  pipeline_call( '/repo', 2026, 5, 1, 3 ),
  '/repo/pipeline_slot_nrt.csh 2026 5 1 3',
  'pipeline call'
);
is(
  pipeline_shell_command( '/repo', '/logs', 2026, 5, 1, 3 ),
  '/repo/pipeline_slot_nrt.csh 2026 5 1 3 > /logs/20260501_03.log 2>&1',
  'pipeline shell command with log redirect'
);

done_testing;
