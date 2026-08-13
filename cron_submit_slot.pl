#!/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use v5.38;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::DrmsRuntime    qw(configure_drms_environment);
use AIALimbfit::LimbfitCommand qw(validate_limbfit_args);
use File::Path                 qw(make_path);
use Getopt::Long;

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
configure_drms_environment($cfg);

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
) or die "Invalid options\n";
validate_limbfit_args( year => $yr, month => $mo, day => $da, hour => $hr );
exit 0 if $hr % ( $cfg->{cadence_h} // 3 );

umask 0002;
my $run       = sprintf '%d%.2d%.2d_%.2d', $yr, $mo, $da, $hr;
my $stage_dir = "$cfg->{pointing_dir}/$run";
my @steps     = (
  [
    'limbfit',    $^X,        "$RealBin/run_limbfit_ymdh.pl", "-year=$yr",
    "-month=$mo", "-day=$da", "-hour=$hr"
  ],
  [
    'reduce', $^X, "$RealBin/lf2mpr_nrt.pdl", "-year=$yr", "-month=$mo", "-day=$da",
    "-hour=$hr", "-inpdir=$cfg->{fits_root}", "-outdir=$stage_dir"
  ],
  [ 'publish', $^X, "$RealBin/update3h_mpt.pl", "-srcdir=$stage_dir", '-delete' ],
);

if ($dry_run) {
  print join( q{ }, @{$_}[ 1 .. $#{$_} ] ), "\n" for @steps;
  exit 0;
}

make_path( $cfg->{logs_dir},     { chmod => oct('755') } ) unless -d $cfg->{logs_dir};
make_path( $cfg->{pointing_dir}, { chmod => oct('755') } ) unless -d $cfg->{pointing_dir};
my $log_path = "$cfg->{logs_dir}/$run.log";
open my $saved_stdout, '>&', \*STDOUT  or die "Cannot save STDOUT: $!\n";
open my $saved_stderr, '>&', \*STDERR  or die "Cannot save STDERR: $!\n";
open STDOUT,           '>',  $log_path or die "Cannot write '$log_path': $!\n";
open STDERR,           '>&', \*STDOUT  or die "Cannot redirect STDERR: $!\n";

my ( $failed_step, $status );
for my $step (@steps) {
  my ( $name, @command ) = @{$step};
  warn "PIPELINE START slot=$run step=$name\n";
  $status = system { $command[0] } @command;
  if ( $status != 0 ) {
    $failed_step = $name;
    last;
  }
  warn "PIPELINE OK slot=$run step=$name\n";
}

open STDOUT, '>&', $saved_stdout or die "Cannot restore STDOUT: $!\n";
open STDERR, '>&', $saved_stderr or die "Cannot restore STDERR: $!\n";
if ( !defined $failed_step ) {
  rmdir $stage_dir;
  exit 0;
}

my $message    = "pipeline failed for $run at $failed_step: " . _status_text($status) . "\n";
my @recipients = grep { length } split /,/, ( $cfg->{mail_to} // q{} );
if (@recipients) {
  my @tail;
  if ( open my $log_fh, '<', $log_path ) {
    @tail = <$log_fh>;
    close $log_fh or warn "Can't close '$log_path': $!\n";
    splice @tail, 0, @tail - 20 if @tail > 20;
  }
  if ( open my $mail_fh, q{|-}, q{mailx}, '-s', "3h MPT pipeline failed $run", @recipients ) {
    print {$mail_fh} $message, "$log_path\n\n", @tail;
    close $mail_fh or warn "mailx failed: $?\n";
  }
  else {
    warn "cannot start mailx: $!\n";
  }
}
die $message;

sub _status_text ($status) {
  return "exec error: $!" if $status == -1;
  return 'signal ' . ( $status & 127 ) if $status & 127;
  return 'exit ' . ( $status >> 8 );
}
