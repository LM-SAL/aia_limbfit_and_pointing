#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::CronSlot qw(default_slot_from_epoch pipeline_shell_command run_id should_run_hour);
use Getopt::Long;
use File::Path qw(make_path);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{SUMSERVER} = $cfg->{sumserver};
local $ENV{SGE_ROOT}  = $cfg->{sge_root};
local $ENV{TZ}        = $cfg->{tz};
umask 0002;
my $dry_run = 0;
my ( $yr, $mo, $da, $hr ) = default_slot_from_epoch(time);
GetOptions(
  'year=i'  => \$yr,
  'month=i' => \$mo,
  'day=i'   => \$da,
  'hour=i'  => \$hr,
  'dry-run' => \$dry_run,
);
exit unless should_run_hour($hr);
my $log = $cfg->{logs_dir};
make_path( $log, { chmod => oct('755') } ) unless -d $log;
my $cmd = pipeline_shell_command( $cfg->{repo_root}, $log, $yr, $mo, $da, $hr );

if ($dry_run) {
  print "$cmd\n";
  exit 0;
}
my $run = run_id( $yr, $mo, $da, $hr );
system($cmd) == 0
  or die "pipeline failed for $run: exit=$?\n";
