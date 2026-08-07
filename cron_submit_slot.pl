#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
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
exit 0 if system($cmd) == 0;

my $message    = "pipeline failed for $run: exit=$?\n";
my @recipients = split /,/, ( $cfg->{mail_to} // q{} );
if (@recipients) {
  my @tail;
  if ( open my $log_fh, '<', "$log/$run.log" ) {
    @tail = <$log_fh>;
    close $log_fh or warn "Can't close '$log/$run.log': $!\n";
    splice @tail, 0, @tail - 20 if @tail > 20;
  }
  if ( open my $mail_fh, q{|-}, q{mailx}, '-s', "3h MPT pipeline failed $run", @recipients ) {
    print {$mail_fh} $message, "$log/$run.log\n\n", @tail;
    close $mail_fh or warn "mailx failed: $?\n";
  }
  else {
    warn "cannot start mailx: $!\n";
  }
}
die $message;
