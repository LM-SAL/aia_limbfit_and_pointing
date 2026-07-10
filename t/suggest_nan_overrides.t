use strict;
use warnings;
use FindBin        qw($Bin);
use File::Basename qw(dirname);
use File::Copy     qw(copy);
use File::Path     qw(make_path);
use File::Temp     qw(tempdir);
use Test::More;

sub perl_quote {
  my ($value) = @_;
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

sub write_masterpoint {
  my ( $path, $x335, $y335 ) = @_;
  open my $fh, '>', $path or die "Cannot write $path: $!";
  print {$fh} "KWD A_171_X0\t100.000000\n";
  print {$fh} "KWD A_171_Y0\t200.000000\n\n";
  print {$fh} "KWD A_335_X0\t$x335\n";
  print {$fh} "KWD A_335_Y0\t$y335\n\n";
  close $fh or die "Cannot close $path: $!";
  return;
}

sub write_limb {
  my ( $path, $x, $y, $radius_offset ) = @_;
  make_path( dirname($path) );
  open my $fh, '>', $path or die "Cannot write $path: $!";
  my $radius = 30 + $radius_offset;
  print {$fh} "$x $y $radius 0 2026-07-07T00:00:00Z 30\n" for 1 .. 12;
  close $fh or die "Cannot close $path: $!";
  return;
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $src  = "$tmp/masterpoints";
my $out  = "$tmp/overrides";
my $fits = "$tmp/fits";
make_path($src);

write_masterpoint( "$src/masterpoint_20260707_0130_3hcadence.txt", '2040.000000', '2047.000000' );
write_masterpoint( "$src/masterpoint_20260707_0430_3hcadence.txt", 'NaN',         'NaN' );
write_masterpoint( "$src/masterpoint_20260707_0730_3hcadence.txt", '2042.000000', '2046.000000' );
write_masterpoint( "$src/masterpoint_20260710_0430_3hcadence.txt", 'NaN',         'NaN' );
write_masterpoint( "$src/masterpoint_20260712_0430_3hcadence.txt", '2045.000000', '2044.000000' );

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  wl => [171, 335],\n";
print {$cfg_fh} "  pointing_dir => ", perl_quote($src), ",\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;
my $output = qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 2>&1);
is( $? >> 8, 0, 'suggestion scan exits successfully' ) or diag $output;
like(
  $output,
  qr{SUGGEST\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+2041[.]000000\s+2046[.]500000},
  'NaN pair is interpolated between the nearest finite records'
);
like(
  $output,
  qr{previous=masterpoint_20260707_0130_3hcadence[.]txt},
  'previous source is reported'
);
like( $output, qr{next=masterpoint_20260707_0730_3hcadence[.]txt}, 'next source is reported' );
like(
  $output,
  qr{UNRESOLVED\s+masterpoint_20260710_0430_3hcadence[.]txt\s+335.*reason=anchor_gap},
  'suggestions do not interpolate across distant anchors by default'
);
ok( !-e $out, 'default scan is read-only' );

$output =
  qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 -outdir="$out" 2>&1);
is( $? >> 8, 0, 'override-file generation exits successfully' ) or diag $output;
my $override = "$out/masterpoint_20260707_0430_3hcadence.overrides.txt";
ok( -e $override, 'one override file is written for the affected slot' );
open my $override_fh, '<', $override or die "Cannot read $override: $!";
my $content = do { local $/; <$override_fh> };
close $override_fh or die "Cannot close $override: $!";
like(
  $content,
  qr{^# target: masterpoint_20260707_0430_3hcadence[.]txt$}m,
  'override records its target'
);
like(
  $content,
  qr{^# previous: masterpoint_20260707_0130_3hcadence[.]txt$}m,
  'override records its previous source'
);
like(
  $content,
  qr{^# next: masterpoint_20260707_0730_3hcadence[.]txt$}m,
  'override records its next source'
);
like( $content, qr{^335 2041[.]000000 2046[.]500000$}m, 'output is reducer-compatible' );

write_limb( "$fits/2026/07/07/20260707_00_0335.limb", 2040, 2047,   0 );
write_limb( "$fits/2026/07/07/20260707_03_0335.limb", 2041, 2046.5, 0 );
write_limb( "$fits/2026/07/07/20260707_06_0335.limb", 2042, 2046,   0 );

my $limb_out = "$tmp/limb_overrides";
$output =
qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 -fits-root="$fits" -outdir="$limb_out" -radius-tolerance=1 -neighbor-tolerance=0.25 -agreement-tolerance=0.25 -min-limb-samples=10 2>&1);
is( $? >> 8, 0, 'limb-aware suggestion exits successfully' ) or diag $output;
like(
  $output,
qr{AGREE\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+2041[.]000000\s+2046[.]500000.*confidence=HIGH},
  'matching limb and temporal evidence produces a high-confidence suggestion'
);
my $limb_override = "$limb_out/masterpoint_20260707_0430_3hcadence.overrides.txt";
ok( -e $limb_override, 'agreement writes a limb-validated override file' );
open my $limb_override_fh, '<', $limb_override or die "Cannot read $limb_override: $!";
my $limb_content = do { local $/; <$limb_override_fh> };
close $limb_override_fh or die "Cannot close $limb_override: $!";
like(
  $limb_content,
  qr{^# method: limb validated by temporal interpolation$}m,
  'override records its evidence method'
);
like( $limb_content, qr{^# confidence: HIGH$}m, 'override records confidence' );

unlink "$fits/2026/07/07/20260707_03_0335.limb" or die "Cannot remove target limb: $!";
my $no_limb_out = "$tmp/no_limb_overrides";
$output =
qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 -fits-root="$fits" -outdir="$no_limb_out" -radius-tolerance=1 -neighbor-tolerance=0.25 -agreement-tolerance=0.25 -min-limb-samples=10 2>&1);
is( $? >> 8, 0, 'missing-limb suggestion exits successfully' ) or diag $output;
like(
  $output,
  qr{NO_LIMB_CANDIDATE\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335},
  'missing target limb is reported'
);
like(
  $output,
qr{BEST_GUESS\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+2041[.]000000\s+2046[.]500000.*confidence=REVIEW_REQUIRED},
  'missing target limb falls back to the bounded temporal candidate'
);

write_limb( "$fits/2026/07/07/20260707_03_0335.limb", 2050, 2050, 0 );
my $conflict_out = "$tmp/conflict_overrides";
$output =
qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 -fits-root="$fits" -outdir="$conflict_out" -radius-tolerance=1 -neighbor-tolerance=0.25 -agreement-tolerance=0.25 -min-limb-samples=10 2>&1);
is( $? >> 8, 0, 'limb-aware conflict scan exits successfully' ) or diag $output;
like(
  $output,
  qr{CONFLICT\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335},
  'disagreeing limb and temporal evidence is reported as a conflict'
);
like(
  $output,
qr{BEST_GUESS\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+2050[.]000000\s+2050[.]000000.*confidence=REVIEW_REQUIRED},
  'conflict emits the radius-consistent limb value as a reviewable best guess'
);
my $conflict_override = "$conflict_out/masterpoint_20260707_0430_3hcadence.overrides.txt";
ok( -e $conflict_override, 'conflict writes a reviewable override file' );
open my $conflict_fh, '<', $conflict_override or die "Cannot read $conflict_override: $!";
my $conflict_content = do { local $/; <$conflict_fh> };
close $conflict_fh or die "Cannot close $conflict_override: $!";
like(
  $conflict_content,
  qr{^# confidence: REVIEW_REQUIRED$}m,
  'conflict override is marked for review'
);
like(
  $conflict_content,
  qr{^335 2050[.]000000 2050[.]000000$}m,
  'conflict override remains reducer-compatible'
);

write_limb( "$fits/2026/07/07/20260707_03_0335.limb", 2041, 2046.5, 0 );
write_limb( "$fits/2026/07/07/20260707_00_0335.limb", 100,  100,    0 );
$output =
qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$src" -wavelength=335 -fits-root="$fits" -radius-tolerance=1 -neighbor-tolerance=0.25 -agreement-tolerance=0.25 -min-limb-samples=10 2>&1);
is( $? >> 8, 0, 'biased-anchor scan exits successfully' ) or diag $output;
like(
  $output,
  qr{UNRESOLVED\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+previous=NONE},
  'neighboring masterpoint is excluded when its limb evidence disagrees'
);

my $real_src  = "$tmp/real_masterpoints";
my $real_fits = "$tmp/real_fits";
my $real_out  = "$tmp/real_overrides";
make_path($real_src);
write_masterpoint( "$real_src/masterpoint_20260707_0130_3hcadence.txt",
  '2042.000000', '2046.500000' );
write_masterpoint( "$real_src/masterpoint_20260707_0430_3hcadence.txt", 'NaN', 'NaN' );
write_masterpoint( "$real_src/masterpoint_20260707_0730_3hcadence.txt",
  '2042.000000', '2046.500000' );
write_limb( "$real_fits/2026/07/07/20260707_00_0335.limb", 2042, 2046.5, 0 );
write_limb( "$real_fits/2026/07/07/20260707_06_0335.limb", 2042, 2046.5, 0 );
copy( "$repo/data/20260707_03_0335.limb", "$real_fits/2026/07/07/20260707_03_0335.limb" )
  or die "Cannot copy real conflict fixture: $!";
$output =
qx("$^X" "$repo/suggest_nan_overrides.pl" -srcdir="$real_src" -wavelength=335 -fits-root="$real_fits" -outdir="$real_out" 2>&1);
is( $? >> 8, 0, 'real bimodal conflict scan exits successfully' ) or diag $output;
like(
  $output,
qr{BEST_GUESS\s+masterpoint_20260707_0430_3hcadence[.]txt\s+335\s+2040[.]554000\s+2046[.]711556.*confidence=REVIEW_REQUIRED},
  'real bimodal conflict emits the radius-consistent limb value'
);

done_testing;
