use strict;
use warnings;
use FindBin qw($Bin);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

sub perl_quote {
  my ($value) = @_;
  $value =~ s/\\/\\\\/g;
  $value =~ s/'/\\'/g;
  return "'$value'";
}

my $repo = "$Bin/..";
my $tmp  = tempdir( CLEANUP => 1 );
my $inp  = "$tmp/inp";
my $out  = "$tmp/out";
my $stg  = "$tmp/stage";
make_path("$inp/2026/05/01");

my $limb = "$inp/2026/05/01/20260501_00_4500.limb";
open my $limb_fh, '>', $limb or die "Cannot write $limb: $!";
print {$limb_fh} "10 20\n";
print {$limb_fh} "1234567 1234567\n";
close $limb_fh or die "Cannot close $limb: $!";
copy( "$repo/data/20260707_03_0335.limb", "$inp/2026/05/01/20260501_00_0335.limb" )
  or die "Cannot copy bimodal fixture: $!";

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  wl => [335, 4500],\n";
print {$cfg_fh} "  cadence_h => 3,\n";
print {$cfg_fh} "  pointing_dir => ", perl_quote($stg), ",\n";
print {$cfg_fh} "  nan_sentinel => 1234567,\n";
print {$cfg_fh} "  split_cluster_mode => 'ignore',\n";
print {$cfg_fh} "};\n";
close $cfg_fh or die "Cannot close $config: $!";

local $ENV{AIA_LIMBFIT_CONFIG} = $config;

my $output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 -inpdir="$inp" -outdir="$out" -stage -stgdir="$stg" 2>&1);
is( $? >> 8, 0, 'lf2mpr_nrt.pdl exits successfully' ) or diag $output;

my $masterpoint = "$out/masterpoint_20260501_0130_3hcadence.txt";
ok( -e $masterpoint, 'masterpoint file uses slot-center filename' );
open my $mp_fh, '<', $masterpoint or die "Cannot read $masterpoint: $!";
my $content = do { local $/; <$mp_fh> };
close $mp_fh or die "Cannot close $masterpoint: $!";

like( $content, qr/^KWD A_4500_X0\t10[.]000000$/m, '4500 sentinel row is excluded from x average' );
like( $content, qr/^KWD A_4500_Y0\t20[.]000000$/m, '4500 sentinel row is excluded from y average' );
like( $content, qr/^KWD A_335_X0\tNaN$/m, 'failed 335 reduction writes NaN x and continues' );
like( $content, qr/^KWD A_335_Y0\tNaN$/m, 'failed 335 reduction writes NaN y and continues' );
ok( -e "$stg/masterpoint_20260501_0130_3hcadence.txt", 'stage copy is written' );

my $overrides = "$tmp/overrides.txt";
open my $override_fh, '>', $overrides or die "Cannot write $overrides: $!";
print {$override_fh} "# wavelength x_center y_center\n335 2040.554 2046.711556\n";
close $override_fh or die "Cannot close $overrides: $!";
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 -inpdir="$inp" -outdir="$out" -override-file="$overrides" 2>&1);
is( $? >> 8, 0, 'explicit override reduction exits successfully' ) or diag $output;
open my $override_out_fh, '<', $masterpoint or die "Cannot read $masterpoint: $!";
my $override_content = do { local $/; <$override_out_fh> };
close $override_out_fh or die "Cannot close $masterpoint: $!";
like( $override_content, qr/^KWD A_335_X0\t2040[.]554000$/m, 'override supplies selected 335 x value' );
like( $override_content, qr/^KWD A_335_Y0\t2046[.]711556$/m, 'override supplies selected 335 y value' );

my $bad_overrides = "$tmp/bad_overrides.txt";
open my $bad_override_fh, '>', $bad_overrides or die "Cannot write $bad_overrides: $!";
print {$bad_override_fh} "335 NaN 2046.704\n";
close $bad_override_fh or die "Cannot close $bad_overrides: $!";
$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 -inpdir="$inp" -outdir="$out" -override-file="$bad_overrides" 2>&1);
isnt( $? >> 8, 0, 'non-finite override is rejected' );
like( $output, qr{Invalid override}, 'invalid override error is explicit' );

open my $old_fh, '>', $masterpoint or die "Cannot write $masterpoint: $!";
print {$old_fh} "ORIGINAL\n";
close $old_fh or die "Cannot close $masterpoint: $!";
unlink "$inp/2026/05/01/20260501_00_0335.limb" or die "Cannot remove test fixture: $!";

$output = qx("$^X" "$repo/lf2mpr_nrt.pdl" -year=2026 -month=5 -day=1 -hour=0 -inpdir="$inp" -outdir="$out" -require-all 2>&1);
isnt( $? >> 8, 0, 'require-all rejects an incomplete wavelength set' );
like( $output, qr{Missing or empty limb files.*335A}, 'missing wavelength is reported' );
open my $kept_fh, '<', $masterpoint or die "Cannot read $masterpoint: $!";
is( do { local $/; <$kept_fh> }, "ORIGINAL\n", 'failed reduction preserves the previous output' );
close $kept_fh or die "Cannot close $masterpoint: $!";

done_testing;
