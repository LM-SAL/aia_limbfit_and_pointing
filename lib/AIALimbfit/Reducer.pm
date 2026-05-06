package AIALimbfit::Reducer;

use strict;
use warnings;
use Exporter qw(import);
use PDL;
use PDL::Stats::Basic;

our @EXPORT_OK = qw(
  detect_split_cluster
  filter_4500_sentinel
  kwd_lines
  limb_input_path
  masterpoint_filename
  reduce_limb_points
);

sub masterpoint_filename {
  my ( $year, $month, $day, $hour, $duration_h ) = @_;
  my $center_h = $hour + $duration_h * 0.5;
  my $minute   = int( 60 * ( $center_h - int($center_h) ) );
  return sprintf 'masterpoint_%d%.2d%.2d_%.2d%.2d_%dhcadence.txt',
    $year, $month, $day, int($center_h), $minute, $duration_h;
}

sub limb_input_path {
  my ( $root, $year, $month, $day, $hour, $wavelength ) = @_;
  return sprintf '%s/%d/%.2d/%.2d/%d%.2d%.2d_%.2d_%.4d.limb',
    $root, $year, $month, $day, $year, $month, $day, $hour, $wavelength;
}

sub detect_split_cluster {    ## no critic (Subroutines::ProhibitExcessComplexity)
  my ( $x0, $y0, $cfg ) = @_;
  return if ( $cfg->{split_cluster_mode} // 'fail' ) eq 'ignore';

  my $n       = $x0->dim(0);
  my $min_seg = $cfg->{split_cluster_min_segment_size} // 20;
  return if $n < 2 * $min_seg;

  my @x = map { $x0->at($_) } 0 .. $n - 1;
  my @y = map { $y0->at($_) } 0 .. $n - 1;
  my @jumps;
  for my $i ( 0 .. $n - 2 ) {
    push @jumps, sqrt( ( $x[ $i + 1 ] - $x[$i] )**2 + ( $y[ $i + 1 ] - $y[$i] )**2 );
  }
  return if @jumps < 3;

  my $max_idx  = 0;
  my $max_jump = $jumps[0];
  for my $i ( 1 .. $#jumps ) {
    if ( $jumps[$i] > $max_jump ) {
      $max_jump = $jumps[$i];
      $max_idx  = $i;
    }
  }

  my @other = @jumps;
  splice @other, $max_idx, 1;
  my ( $ojm, $ojs ) = ( 0, 0 );
  $ojm += $_ for @other;
  $ojm /= @other if @other;
  $ojs += ( $_ - $ojm )**2 for @other;
  $ojs = sqrt( $ojs / ( @other - 1 ) ) if @other > 1;

  my $second_jump = $other[0];
  for (@other) { $second_jump = $_ if $_ > $second_jump; }

  my $n1 = $max_idx + 1;
  my $n2 = $n - $n1;
  return if $n1 < $min_seg || $n2 < $min_seg;

  my ( $xm1, $xm2, $ym1, $ym2 ) = ( 0, 0, 0, 0 );
  $xm1 += $x[$_] for 0 .. $max_idx;
  $ym1 += $y[$_] for 0 .. $max_idx;
  $xm2 += $x[$_] for $max_idx + 1 .. $#x;
  $ym2 += $y[$_] for $max_idx + 1 .. $#y;
  $xm1 /= $n1;
  $ym1 /= $n1;
  $xm2 /= $n2;
  $ym2 /= $n2;

  my ( $xs1, $xs2, $ys1, $ys2 ) = ( 0, 0, 0, 0 );
  $xs1 += ( $x[$_] - $xm1 )**2 for 0 .. $max_idx;
  $ys1 += ( $y[$_] - $ym1 )**2 for 0 .. $max_idx;
  $xs2 += ( $x[$_] - $xm2 )**2 for $max_idx + 1 .. $#x;
  $ys2 += ( $y[$_] - $ym2 )**2 for $max_idx + 1 .. $#y;
  $xs1 = sqrt( $xs1 / ( $n1 - 1 ) ) if $n1 > 1;
  $ys1 = sqrt( $ys1 / ( $n1 - 1 ) ) if $n1 > 1;
  $xs2 = sqrt( $xs2 / ( $n2 - 1 ) ) if $n2 > 1;
  $ys2 = sqrt( $ys2 / ( $n2 - 1 ) ) if $n2 > 1;

  my $scat1   = sqrt( $xs1 * $xs1 + $ys1 * $ys1 );
  my $scat2   = sqrt( $xs2 * $xs2 + $ys2 * $ys2 );
  my $scatter = $scat1 > $scat2 ? $scat1 : $scat2;

  my $jump_threshold = $ojm + ( $cfg->{split_cluster_jump_sigma} // 6 ) * $ojs;
  my $jump_ratio     = $second_jump > 0 ? $max_jump / $second_jump : 1_000_000;
  my $center_sep     = sqrt( ( $xm1 - $xm2 )**2 + ( $ym1 - $ym2 )**2 );
  my $sep_ratio      = $scatter > 0 ? $center_sep / $scatter : 1_000_000;

  return
       if $max_jump <= $jump_threshold
    || $jump_ratio <= ( $cfg->{split_cluster_jump_ratio}       // 3 )
    || $sep_ratio <=  ( $cfg->{split_cluster_separation_ratio} // 10 );

  return 1;
}

sub filter_4500_sentinel {
  my ( $x0, $y0, $sentinel ) = @_;
  my $valid = which( ( $x0 != $sentinel ) & ( $y0 != $sentinel ) );
  return ( $x0->index($valid), $y0->index($valid) );
}

sub reduce_limb_points {
  my ( $x0, $y0, $wavelength, $cfg ) = @_;
  my $pass1_baseline = $cfg->{sigma_clip_pass1_baseline} // 'zero';
  my $pass2_baseline = $cfg->{sigma_clip_pass2_baseline} // 'mean';
  my $pass1_sigma    = $cfg->{sigma_clip_pass1_sigma}    // 2;
  my $pass2_sigma    = $cfg->{sigma_clip_pass2_sigma}    // 3;
  my $split_mode     = $cfg->{split_cluster_mode}        // 'fail';

  if ( $wavelength == 4500 ) {
    ( $x0, $y0 ) = filter_4500_sentinel( $x0, $y0, $cfg->{nan_sentinel} // 1_234_567 );
  }
  if ( $wavelength != 4500 && $split_mode ne 'ignore' && detect_split_cluster( $x0, $y0, $cfg ) ) {
    die "Split-cluster detected (${wavelength}A)\n";
  }

  my ( $xp2, $yp2 );
  if ( $wavelength == 4500 || $x0->dim(0) < 3 ) {
    $xp2 = $x0;
    $yp2 = $y0;
  }
  else {
    my $xd = $x0 - $x0->avg;
    my $dy = $y0 - $y0->avg;
    my $cd = sqrt( $xd * $xd + $dy * $dy );
    my $mask =
      which( $cd < $pass1_sigma * $cd->stdv + ( $pass1_baseline eq 'mean' ? $cd->avg : 0 ) );
    my $xp = $x0->index($mask);
    my $yp = $y0->index($mask);
    if ( $xp->dim(0) == 0 ) {
      $xp2 = $xp;
      $yp2 = $yp;
    }
    else {
      my $xdp = $xp - $xp->avg;
      my $ydp = $yp - $yp->avg;
      my $cp  = sqrt( $xdp * $xdp + $ydp * $ydp );
      my $m2 =
        which( $cp < $pass2_sigma * $cp->stdv + ( $pass2_baseline eq 'mean' ? $cp->avg : 0 ) );
      $xp2 = $xp->index($m2);
      $yp2 = $yp->index($m2);
    }
  }

  return ( $xp2, $yp2, $xp2->avg, $yp2->avg );
}

sub kwd_lines {
  my ( $wavelength, $x_average, $y_average ) = @_;
  return (
    sprintf( "KWD A_%.3d_X0\t%f\n",   $wavelength, $x_average ),
    sprintf( "KWD A_%.3d_Y0\t%f\n\n", $wavelength, $y_average ),
  );
}

1;
