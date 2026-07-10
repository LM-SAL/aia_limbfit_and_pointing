#!/home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use AIALimbfit::Reducer qw(limb_input_path reduce_limb_points);
use AIALimbfit::Slot    qw(slot_bounds_from_masterpoint ts2ymdh);
use File::Path          qw(make_path);
use Getopt::Long;
use PDL;
use PDL::IO::Misc;
use Scalar::Util qw(looks_like_number);

sub _is_finite {
  my ($value) = @_;
  return
       defined $value
    && $value !~ /(?:nan|inf|missing)/i
    && looks_like_number($value)
    && $value == $value;
}

sub _read_values {
  my ($path) = @_;
  open my $fh, '<', $path or die "Cannot read '$path': $!\n";
  my %values;
  while (<$fh>) {
    next unless /^KWD\s+A_(\d+)_([XY]0)\s+(\S+)/;
    $values{ $1 + 0 }{$2} = $3;
  }
  close $fh or die "Cannot close '$path': $!\n";
  return \%values;
}

sub _finite_pair {
  my ( $masterpoint, $wavelength ) = @_;
  my $values = $masterpoint->{values}{$wavelength};
  return $values && _is_finite( $values->{X0} ) && _is_finite( $values->{Y0} );
}

sub _limb_candidate {
  my ( $masterpoint, $wavelength, %opts ) = @_;
  my ( $year, $month, $day, $hour ) = ts2ymdh( $masterpoint->{start_epoch} );
  my $path = limb_input_path( $opts{fits_root}, $year, $month, $day, $hour, $wavelength );
  return { error => "missing limb file: $path" } unless -s $path;

  my ( $x, $y, $radius, $reference ) = eval { rcols $path, 0, 1, 2, 5 };
  return { error => "cannot read limb file '$path': $@" } if $@;

  my $valid =
    ( $x == $x ) & ( $y == $y ) & ( $radius == $radius ) & ( $reference == $reference ) &
    ( abs($x) < 1e100 ) & ( abs($y) < 1e100 ) & ( abs($radius) < 1e100 ) &
    ( abs($reference) < 1e100 ) & ( abs( $radius - $reference ) <= $opts{radius_tolerance} );
  if ( defined $opts{nan_sentinel} ) {
    $valid = $valid & ( $x != $opts{nan_sentinel} ) & ( $y != $opts{nan_sentinel} ) &
      ( $radius != $opts{nan_sentinel} );
  }

  my $indices  = which($valid);
  my $retained = $indices->dim(0);
  return { error => "only $retained radius-consistent samples in '$path'", retained => $retained }
    if $retained < $opts{min_limb_samples};

  my $filtered_x = $x->index($indices);
  my $filtered_y = $y->index($indices);
  my ( $accepted_x, $accepted_y, $x_center, $y_center ) =
    eval { reduce_limb_points( $filtered_x, $filtered_y, $wavelength, $opts{cfg} ) };
  return { error => "reducer failed for '$path': $@", retained => $retained } if $@;
  my $accepted = $accepted_x->dim(0);
  return {
    error    => "only $accepted accepted samples in '$path'",
    retained => $retained,
    accepted => $accepted
    }
    if $accepted < $opts{min_limb_samples};
  return { error => "non-finite limb candidate from '$path'" }
    unless _is_finite($x_center) && _is_finite($y_center);

  return {
    path     => $path,
    x        => $x_center + 0,
    y        => $y_center + 0,
    retained => $retained,
    accepted => $accepted,
  };
}

sub _cached_limb_candidate {
  my ( $cache, $masterpoint, $wavelength, %opts ) = @_;
  my $key = "$masterpoint->{name}:$wavelength";
  $cache->{$key} //= _limb_candidate( $masterpoint, $wavelength, %opts );
  return $cache->{$key};
}

sub _trusted_anchor {
  my ( $masterpoint, $wavelength, %opts ) = @_;
  return                            unless _finite_pair( $masterpoint, $wavelength );
  return { record => $masterpoint } unless defined $opts{fits_root};

  my $limb = _cached_limb_candidate( $opts{cache}, $masterpoint, $wavelength, %opts );
  if ( $limb->{error} ) {
    ( my $reason = $limb->{error} ) =~ s/\s+/ /g;
    print "SKIP_ANCHOR $masterpoint->{name} $wavelength reason=$reason\n";
    return;
  }
  my $dx    = $masterpoint->{values}{$wavelength}{X0} - $limb->{x};
  my $dy    = $masterpoint->{values}{$wavelength}{Y0} - $limb->{y};
  my $delta = sqrt( $dx * $dx + $dy * $dy );
  if ( $delta > $opts{neighbor_tolerance} ) {
    printf "SKIP_ANCHOR %s %d table=%.6f,%.6f limb=%.6f,%.6f table_limb_delta=%.6f\n",
      $masterpoint->{name}, $wavelength, $masterpoint->{values}{$wavelength}{X0},
      $masterpoint->{values}{$wavelength}{Y0}, $limb->{x}, $limb->{y}, $delta;
    return;
  }
  return { record => $masterpoint, limb => $limb, delta => $delta };
}

my $config_file = $ENV{AIA_LIMBFIT_CONFIG} // "$RealBin/config.pl";
my $cfg         = do $config_file or die "Cannot load $config_file: " . ( $@ || $! );
my $srcdir      = $cfg->{pointing_dir};
my $outdir;
my $fits_root;
my $radius_tolerance     = 1;
my $neighbor_tolerance   = 0.75;
my $agreement_tolerance  = 0.75;
my $min_limb_samples     = 10;
my $max_anchor_gap_hours = 24;
my @wavelengths;

GetOptions(
  'srcdir=s'               => \$srcdir,
  'outdir=s'               => \$outdir,
  'fits-root=s'            => \$fits_root,
  'wavelength=i'           => \@wavelengths,
  'radius-tolerance=f'     => \$radius_tolerance,
  'neighbor-tolerance=f'   => \$neighbor_tolerance,
  'agreement-tolerance=f'  => \$agreement_tolerance,
  'min-limb-samples=i'     => \$min_limb_samples,
  'max-anchor-gap-hours=f' => \$max_anchor_gap_hours,
) or die "Invalid options\n";

die "Source directory is required\n"        unless defined $srcdir;
die "Source directory not found: $srcdir\n" unless -d $srcdir;
die "Limb root not found: $fits_root\n"       if defined $fits_root && !-d $fits_root;
die "Radius tolerance must be positive\n"     if !( $radius_tolerance > 0 );
die "Neighbor tolerance must be positive\n"   if !( $neighbor_tolerance > 0 );
die "Agreement tolerance must be positive\n"  if !( $agreement_tolerance > 0 );
die "Minimum limb samples must be positive\n" if !( $min_limb_samples > 0 );
die "Maximum anchor gap must be positive\n"   if !( $max_anchor_gap_hours > 0 );
@wavelengths = @{ $cfg->{wl} // [] }        unless @wavelengths;
die "At least one wavelength is required\n" unless @wavelengths;

opendir my $dh, $srcdir or die "Cannot open '$srcdir': $!\n";
my @names = sort grep { /^masterpoint_\d{8}_\d{4}_\d+hcadence[.]txt$/ } readdir $dh;
closedir $dh;
die "No masterpoint files found in '$srcdir'\n" unless @names;

my @records;
for my $name (@names) {
  my $slot = slot_bounds_from_masterpoint($name) or next;
  push @records,
    {
    name         => $name,
    center_epoch => $slot->{center_epoch},
    start_epoch  => $slot->{start_epoch},
    values       => _read_values("$srcdir/$name"),
    };
}
@records = sort { $a->{center_epoch} <=> $b->{center_epoch} } @records;
die "No valid masterpoint files found in '$srcdir'\n" unless @records;

my %suggestions;
my %limb_cache;
my %evidence_opts = (
  fits_root           => $fits_root,
  radius_tolerance    => $radius_tolerance,
  neighbor_tolerance  => $neighbor_tolerance,
  agreement_tolerance => $agreement_tolerance,
  min_limb_samples    => $min_limb_samples,
  nan_sentinel        => $cfg->{nan_sentinel},
  cfg                 => $cfg,
  cache               => \%limb_cache,
);
for my $i ( 0 .. $#records ) {
  my $target = $records[$i];
  for my $wavelength (@wavelengths) {
    next if _finite_pair( $target, $wavelength );

    my ( $previous, $next );
    for ( my $j = $i - 1 ; $j >= 0 ; $j-- ) {
      if ( my $anchor = _trusted_anchor( $records[$j], $wavelength, %evidence_opts ) ) {
        $previous = $anchor;
        last;
      }
    }
    for my $j ( $i + 1 .. $#records ) {
      if ( my $anchor = _trusted_anchor( $records[$j], $wavelength, %evidence_opts ) ) {
        $next = $anchor;
        last;
      }
    }

    if ( !$previous || !$next ) {
      printf "UNRESOLVED %s %d previous=%s next=%s\n",
        $target->{name}, $wavelength,
        $previous ? $previous->{record}{name} : 'NONE',
        $next     ? $next->{record}{name}     : 'NONE';
      next;
    }

    my $previous_record = $previous->{record};
    my $next_record     = $next->{record};
    my $previous_gap_h  = ( $target->{center_epoch} - $previous_record->{center_epoch} ) / 3600;
    my $next_gap_h      = ( $next_record->{center_epoch} - $target->{center_epoch} ) / 3600;
    if ( $previous_gap_h > $max_anchor_gap_hours || $next_gap_h > $max_anchor_gap_hours ) {
      printf
"UNRESOLVED %s %d previous=%s next=%s reason=anchor_gap previous_hours=%.1f next_hours=%.1f max_hours=%.1f\n",
        $target->{name}, $wavelength, $previous_record->{name}, $next_record->{name},
        $previous_gap_h, $next_gap_h, $max_anchor_gap_hours;
      next;
    }
    my $span = $next_record->{center_epoch} - $previous_record->{center_epoch};
    die "Non-positive interpolation span around '$target->{name}'\n" if $span <= 0;
    my $fraction = ( $target->{center_epoch} - $previous_record->{center_epoch} ) / $span;
    my $temporal_x =
      $previous_record->{values}{$wavelength}{X0} +
      $fraction *
      ( $next_record->{values}{$wavelength}{X0} - $previous_record->{values}{$wavelength}{X0} );
    my $temporal_y =
      $previous_record->{values}{$wavelength}{Y0} +
      $fraction *
      ( $next_record->{values}{$wavelength}{Y0} - $previous_record->{values}{$wavelength}{Y0} );

    my ( $x,      $y )          = ( $temporal_x, $temporal_y );
    my ( $method, $confidence ) = ( 'temporal interpolation', 'PROPOSED' );
    my ( $limb,   $delta );
    if ( defined $fits_root ) {
      $limb = _cached_limb_candidate( \%limb_cache, $target, $wavelength, %evidence_opts );
      if ( $limb->{error} ) {
        ( my $reason = $limb->{error} ) =~ s/\s+/ /g;
        printf "NO_LIMB_CANDIDATE %s %d temporal=%.6f,%.6f reason=%s\n",
          $target->{name}, $wavelength, $temporal_x, $temporal_y, $reason;
        $limb = undef;
        ( $method, $confidence ) =
          ( 'temporal interpolation; no limb candidate', 'REVIEW_REQUIRED' );
      }
      else {
        my $dx = $limb->{x} - $temporal_x;
        my $dy = $limb->{y} - $temporal_y;
        $delta = sqrt( $dx * $dx + $dy * $dy );
        if ( $delta > $agreement_tolerance ) {
          printf
            "CONFLICT %s %d temporal=%.6f,%.6f limb=%.6f,%.6f delta=%.6f previous=%s next=%s\n",
            $target->{name}, $wavelength, $temporal_x, $temporal_y, $limb->{x}, $limb->{y}, $delta,
            $previous_record->{name}, $next_record->{name};
          ( $x,      $y ) = ( $limb->{x}, $limb->{y} );
          ( $method, $confidence ) =
            ( 'radius-consistent limb candidate; temporal conflict', 'REVIEW_REQUIRED' );
        }
        else {
          ( $x, $y ) = ( $limb->{x}, $limb->{y} );
          ( $method, $confidence ) = ( 'limb validated by temporal interpolation', 'HIGH' );
        }
      }
    }

    my $suggestion = {
      wavelength => $wavelength,
      x          => $x,
      y          => $y,
      previous   => $previous_record->{name},
      next       => $next_record->{name},
      fraction   => $fraction,
      method     => $method,
      confidence => $confidence,
      temporal_x => $temporal_x,
      temporal_y => $temporal_y,
      limb       => $limb,
      delta      => $delta,
    };
    push @{ $suggestions{ $target->{name} } }, $suggestion;
    if ( $confidence eq 'HIGH' ) {
      printf
"AGREE %s %d %.6f %.6f temporal=%.6f,%.6f delta=%.6f accepted=%d previous=%s next=%s confidence=%s\n",
        $target->{name}, $wavelength, $x, $y, $temporal_x, $temporal_y, $delta, $limb->{accepted},
        $previous_record->{name}, $next_record->{name}, $confidence;
    }
    elsif ( $confidence eq 'REVIEW_REQUIRED' ) {
      printf "BEST_GUESS %s %d %.6f %.6f method=%s previous=%s next=%s confidence=%s\n",
        $target->{name}, $wavelength, $x, $y, $method, $previous_record->{name},
        $next_record->{name}, $confidence;
    }
    else {
      printf "SUGGEST %s %d %.6f %.6f previous=%s next=%s fraction=%.6f\n",
        $target->{name}, $wavelength, $x, $y, $previous_record->{name}, $next_record->{name},
        $fraction;
    }
  }
}

if ( defined $outdir ) {
  make_path( $outdir, { chmod => oct('755') } ) unless -d $outdir;
  for my $target ( sort keys %suggestions ) {
    ( my $filename = $target ) =~ s/[.]txt$/.overrides.txt/;
    my $path = "$outdir/$filename";
    my $tmp  = "$path.$$";
    open my $fh, '>', $tmp or die "Cannot write '$tmp': $!\n";
    print {$fh} "# target: $target\n";
    for my $suggestion ( @{ $suggestions{$target} } ) {
      print {$fh} "# wavelength: $suggestion->{wavelength}\n";
      print {$fh} "# method: $suggestion->{method}\n";
      print {$fh} "# confidence: $suggestion->{confidence}\n";
      print {$fh} "# previous: $suggestion->{previous}\n";
      print {$fh} "# next: $suggestion->{next}\n";
      if ( my $limb = $suggestion->{limb} ) {
        print  {$fh} "# limb: $limb->{path}\n";
        print  {$fh} "# limb samples: retained=$limb->{retained} accepted=$limb->{accepted}\n";
        printf {$fh} "# temporal candidate: %.6f %.6f\n",
          $suggestion->{temporal_x}, $suggestion->{temporal_y};
        printf {$fh} "# agreement delta: %.6f\n", $suggestion->{delta};
      }
      printf {$fh} "%d %.6f %.6f\n", $suggestion->{wavelength}, $suggestion->{x}, $suggestion->{y};
    }
    close $fh or die "Cannot close '$tmp': $!\n";
    rename $tmp, $path or die "Cannot replace '$path': $!\n";
    print "WROTE $path\n";
  }
}
