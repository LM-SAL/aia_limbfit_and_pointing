use strict;
use warnings;
use FindBin qw($Bin);
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

my $config = "$tmp/config.pl";
open my $cfg_fh, '>', $config or die "Cannot write $config: $!";
print {$cfg_fh} "use strict;\nuse warnings;\nreturn {\n";
print {$cfg_fh} "  wl => [4500],\n";
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
ok( -e "$stg/masterpoint_20260501_0130_3hcadence.txt", 'stage copy is written' );

done_testing;
