#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.42;
use FindBin qw($RealBin);
use Getopt::Long;
use File::Path qw(make_path);

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
local $ENV{SUMSERVER} = $cfg->{sumserver};
local $ENV{SGE_ROOT}  = $cfg->{sge_root};
local $ENV{TZ}        = $cfg->{tz};
umask 0002;
my $dry_run = 0;
my ( undef, undef, $hr, $da, $mo, $yr ) = gmtime( time - 79_200 );
$yr += 1900;
$mo++;
GetOptions(
  'year=i'  => \$yr,
  'month=i' => \$mo,
  'day=i'   => \$da,
  'hour=i'  => \$hr,
  'dry-run' => \$dry_run,
);
exit unless $hr % 3 == 0;
my $log = $cfg->{logs_dir};
make_path( $log, { chmod => oct('755') } ) unless -d $log;
my $run = sprintf '%d%.2d%.2d_%.2d', $yr, $mo, $da, $hr;
my $cmd = "$cfg->{repo_root}/pipeline_slot_nrt.csh $yr $mo $da $hr > $log/$run.log 2>&1";

if ($dry_run) {
  print "$cmd\n";
  exit 0;
}
system($cmd) == 0
  or die "pipeline failed for $run: exit=$?\n";
