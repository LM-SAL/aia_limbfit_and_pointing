use v5.38;
use FindBin qw($Bin);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub quote ($value) {
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

sub config ( $path, $input, $output, @wavelengths ) {
  open my $fh, '>', $path or die "Cannot write $path: $!";
  print {$fh} "use v5.38;\nreturn {\n";
  print {$fh} '  wl => [', join( ',', @wavelengths ), "],\n";
  print {$fh} "  cadence_h => 3,\n";
  print {$fh} "  fits_root => ",    quote($input),  ",\n";
  print {$fh} "  pointing_dir => ", quote($output), ",\n";
  print {$fh} "  nan_sentinel => 1234567,\n";
  print {$fh} "  split_cluster_min_segment_size => 20,\n";
  print {$fh} "  split_cluster_separation_ratio => 10,\n";
  print {$fh} "};\n";
  close $fh or die "Cannot close $path: $!";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $inp  = "$tmp/in";
my $out  = "$tmp/out";
make_path("$inp/2026/05/01");
my $limb = "$inp/2026/05/01/20260501_00_4500.limb";
open my $limb_fh, '>', $limb or die "Cannot write $limb: $!";
print {$limb_fh} "10 20\n1234567 1234567\n";
close $limb_fh or die "Cannot close $limb: $!";

my $cfg = "$tmp/config.pl";
config( $cfg, $inp, $out, 4500 );
local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;
my $output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 2>&1);
is( $? >> 8, 0, 'complete finite slot reduces successfully' ) or diag $output;
my $masterpoint = "$out/masterpoint_20260501_0130_3hcadence.txt";
ok( -s $masterpoint, 'complete masterpoint is written' );
open my $mp_fh, '<', $masterpoint or die "Cannot read $masterpoint: $!";
my $content = do { local $/; <$mp_fh> };
close $mp_fh or die "Cannot close $masterpoint: $!";
like( $content, qr/^KWD A_4500_X0\t10[.]000000$/m, 'sentinel row is excluded' );

my $partial_out = "$tmp/partial";
my $partial_cfg = "$tmp/partial.pl";
config( $partial_cfg, $inp, $partial_out, 94, 4500 );
local $ENV{AIA_LIMBFIT_CONFIG} = $partial_cfg;
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 -wavel=4500 2>&1);
is( $? >> 8, 0, 'explicit wavelength creates a partial repair' ) or diag $output;
my $partial_masterpoint = "$partial_out/masterpoint_20260501_0130_3hcadence.txt";
open my $partial_fh, '<', $partial_masterpoint or die "Cannot read $partial_masterpoint: $!";
my $partial_content = do { local $/; <$partial_fh> };
close $partial_fh or die "Cannot close $partial_masterpoint: $!";
like( $partial_content, qr/^KWD A_4500_X0/m, 'partial repair contains requested wavelength' );
unlike( $partial_content, qr/^KWD A_094_X0/m, 'partial repair omits other wavelengths' );

unlink $limb or die "Cannot remove $limb: $!";
local $ENV{AIA_LIMBFIT_CONFIG} = $cfg;
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 2>&1);
isnt( $? >> 8, 0, 'missing wavelength fails the whole slot' );
like( $output, qr{Missing or empty limb files: 4500A}, 'missing wavelength is named' );
ok( !-e $masterpoint, 'failed retry removes the stale masterpoint' );

my $split_cfg = "$tmp/split.pl";
my $split_in  = "$tmp/split_in";
my $split_out = "$tmp/split_out";
make_path("$split_in/2026/05/01");
copy( "$repo/data/20260326_18_0094.limb", "$split_in/2026/05/01/20260501_00_0094.limb" )
  or die "Cannot copy split fixture: $!";
config( $split_cfg, $split_in, $split_out, 94 );
local $ENV{AIA_LIMBFIT_CONFIG} = $split_cfg;
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 2>&1);
isnt( $? >> 8, 0, 'split cluster fails the whole slot' );
like( $output, qr{split after row 88, segments 88/92}, 'split failure is actionable' );
ok( !-e "$split_out/masterpoint_20260501_0130_3hcadence.txt", 'failed slot writes no masterpoint' );

my $drms = "$tmp/drms";
make_path( "$drms/bin/linux_avx2", "$drms/lib/linux_avx2", "$drms/include" );
my $show_info = "$drms/bin/linux_avx2/show_info";
open my $show_fh, '>', $show_info or die "Cannot write $show_info: $!";
print {$show_fh} <<'FAKE';
#!/usr/bin/env perl
use v5.38;
my $query = $ARGV[-1];
print $query =~ /T00:00:00Z/ ? "10 20\n" : $ENV{BAD_ENDPOINT} ? "NaN 32\n" : "16 32\n";
FAKE
close $show_fh or die "Cannot close $show_info: $!";
chmod 0755, $show_info or die "Cannot chmod $show_info: $!";

my $interpolated_out = "$tmp/interpolated";
my $interpolation_cfg = "$tmp/interpolation.pl";
open my $interpolation_fh, '>', $interpolation_cfg
  or die "Cannot write $interpolation_cfg: $!";
print {$interpolation_fh} "use v5.38;\nreturn {\n";
print {$interpolation_fh} "  wl => [4500], cadence_h => 3, nan_sentinel => 1234567,\n";
print {$interpolation_fh} "  fits_root => '/unused', pointing_dir => ", quote($interpolated_out), ",\n";
print {$interpolation_fh} "  show_info => ", quote($show_info), ", mpt_series => 'test.pointing',\n";
print {$interpolation_fh} "  sumserver => 'test',\n};\n";
close $interpolation_fh or die "Cannot close $interpolation_cfg: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $interpolation_cfg;
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=3 -interpolate-previous=2026-05-01T00:00:00Z -interpolate-next=2026-05-01T06:00:00Z 2>&1);
is( $? >> 8, 0, 'explicit bracketing interpolation succeeds' ) or diag $output;
my $interpolated = "$interpolated_out/masterpoint_20260501_0430_3hcadence.txt";
open my $interpolated_fh, '<', $interpolated or die "Cannot read $interpolated: $!";
my $interpolated_content = do { local $/; <$interpolated_fh> };
close $interpolated_fh or die "Cannot close $interpolated: $!";
like( $interpolated_content, qr/^KWD A_4500_X0\t13[.]000000$/m, 'X center is interpolated' );
like( $interpolated_content, qr/^KWD A_4500_Y0\t26[.]000000$/m, 'Y center is interpolated' );

local $ENV{BAD_ENDPOINT} = 1;
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=3 -interpolate-previous=2026-05-01T00:00:00Z -interpolate-next=2026-05-01T06:00:00Z 2>&1);
isnt( $? >> 8, 0, 'non-finite interpolation endpoint is refused' );
like( $output, qr{Cannot interpolate A_4500_X0: invalid value 'NaN'}, 'bad endpoint is named' );
ok( !-e $interpolated, 'failed interpolation leaves no staged masterpoint' );

done_testing;
