package AIALimbfit::CronSlot;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(default_slot_from_epoch pipeline_call pipeline_shell_command run_id should_run_hour);

sub default_slot_from_epoch {
  my ( $now_epoch, $offset_s ) = @_;
  $offset_s //= 79_200;
  my ( undef, undef, $hour, $day, $month, $year ) = gmtime( $now_epoch - $offset_s );
  return ( $year + 1900, $month + 1, $day, $hour );
}

sub should_run_hour {
  my ($hour) = @_;
  return $hour % 3 == 0;
}

sub run_id {
  my ( $year, $month, $day, $hour ) = @_;
  return sprintf '%d%.2d%.2d_%.2d', $year, $month, $day, $hour;
}

sub pipeline_call {
  my ( $repo_root, $year, $month, $day, $hour ) = @_;
  return "$repo_root/pipeline_slot_nrt.csh $year $month $day $hour";
}

sub pipeline_shell_command {
  my ( $repo_root, $logs_dir, $year, $month, $day, $hour ) = @_;
  my $run = run_id( $year, $month, $day, $hour );
  return pipeline_call( $repo_root, $year, $month, $day, $hour ) . " > $logs_dir/$run.log 2>&1";
}

1;
