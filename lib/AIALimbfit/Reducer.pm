package AIALimbfit::Reducer;

use v5.38;
use Exporter qw(import);
use PDL;

our @EXPORT_OK = qw(
  detect_split_cluster
  kwd_lines
  masterpoint_filename
  reduce_limb_points
);

sub masterpoint_filename ( $year, $month, $day, $hour, $duration_h ) {
  my $center_h = $hour + $duration_h * 0.5;
  my $minute   = int( 60 * ( $center_h - int($center_h) ) );
  return sprintf 'masterpoint_%d%.2d%.2d_%.2d%.2d_%dhcadence.txt',
    $year, $month, $day, int($center_h), $minute, $duration_h;
}

sub _stddev ($values) {
  my $mean = $values->avg;
  return sqrt( ( $values - $mean )->pow(2)->avg );
}

sub detect_split_cluster ( $x0, $y0, $cfg ) {
  my $n       = $x0->dim(0);
  my $min_seg = $cfg->{split_cluster_min_segment_size} // 20;
  return if $n < 2 * $min_seg;

  my $jumps = sqrt( ( $x0->slice( '1:-1' ) - $x0->slice( '0:-2' ) )**2
    + ( $y0->slice( '1:-1' ) - $y0->slice( '0:-2' ) )**2 );
  my $max_idx = $jumps->maximum_ind->at;

  my $n1 = $max_idx + 1;
  my $n2 = $n - $n1;
  return if $n1 < $min_seg || $n2 < $min_seg;

  my $px1 = $x0->slice( "0:$max_idx" );
  my $py1 = $y0->slice( "0:$max_idx" );
  my $px2 = $x0->slice( ( $max_idx + 1 ) . ":" );
  my $py2 = $y0->slice( ( $max_idx + 1 ) . ":" );

  my ( $xm1, $ym1 ) = ( $px1->avg, $py1->avg );
  my ( $xm2, $ym2 ) = ( $px2->avg, $py2->avg );

  my $scatter1 = sqrt( ( $px1 - $xm1 )->pow(2)->avg + ( $py1 - $ym1 )->pow(2)->avg );
  my $scatter2 = sqrt( ( $px2 - $xm2 )->pow(2)->avg + ( $py2 - $ym2 )->pow(2)->avg );
  my $scatter  = $scatter1 > $scatter2 ? $scatter1 : $scatter2;

  my $center_sep = sqrt( ( $xm1 - $xm2 )**2 + ( $ym1 - $ym2 )**2 );
  my $sep_ratio  = $scatter > 0 ? $center_sep / $scatter : 1_000_000;
  return if $sep_ratio <= ( $cfg->{split_cluster_separation_ratio} // 10 );

  return {
    split_after     => $n1,
    first_segment   => $n1,
    second_segment  => $n2,
    separation_ratio => $sep_ratio,
  };
}

sub _filter_4500_sentinel ( $x0, $y0, $sentinel ) {
  my $valid = which( ( $x0 != $sentinel ) & ( $y0 != $sentinel ) );
  return ( $x0->index($valid), $y0->index($valid) );
}

sub reduce_limb_points ( $x0, $y0, $wavelength, $cfg ) {
  my $pass1_sigma = $cfg->{sigma_clip_pass1_sigma} // 2;
  my $pass2_sigma = $cfg->{sigma_clip_pass2_sigma} // 3;

  if ( $wavelength == 4500 ) {
    ( $x0, $y0 ) = _filter_4500_sentinel( $x0, $y0, $cfg->{nan_sentinel} // 1_234_567 );
  }
  if ( $wavelength != 4500 && ( my $split = detect_split_cluster( $x0, $y0, $cfg ) ) ) {
    die sprintf
      "Split-cluster detected (%dA): split after row %d, segments %d/%d, separation/scatter %.1f\n",
      $wavelength, $split->{split_after}, $split->{first_segment}, $split->{second_segment},
      $split->{separation_ratio};
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
    # Inclusive boundary: points exactly on the threshold are retained
    my $pass1_cutoff = $pass1_sigma * _stddev($cd);
    my $mask         = which( $cd <= $pass1_cutoff );
    my $xp = $x0->index($mask);
    my $yp = $y0->index($mask);
    if ( $xp->dim(0) == 0 ) {
      die sprintf
        "All %d limb-fit points rejected by pass 1 (mean distance %.3f, cutoff %.3f); data may be multimodal\n",
        $x0->dim(0), $cd->avg, $pass1_cutoff;
    }
    else {
      my $xdp = $xp - $xp->avg;
      my $ydp = $yp - $yp->avg;
      my $cp  = sqrt( $xdp * $xdp + $ydp * $ydp );
      # Inclusive boundary: points exactly on the threshold are retained
      my $pass2_cutoff = $cp->avg + $pass2_sigma * _stddev($cp);
      my $m2           = which( $cp <= $pass2_cutoff );
      $xp2 = $xp->index($m2);
      $yp2 = $yp->index($m2);
      die sprintf
        "All %d pass-1 limb-fit points rejected by pass 2 (mean distance %.3f, cutoff %.3f)\n",
        $xp->dim(0), $cp->avg, $pass2_cutoff
        if $xp2->dim(0) == 0;
    }
  }

  return ( $xp2, $yp2, $xp2->avg, $yp2->avg );
}

sub kwd_lines ( $wavelength, $x_average, $y_average ) {
  return (
    sprintf( "KWD A_%.3d_X0\t%f\n",   $wavelength, $x_average ),
    sprintf( "KWD A_%.3d_Y0\t%f\n\n", $wavelength, $y_average ),
  );
}

1;
