use v5.42;
use FindBin    qw($Bin);
use File::Temp qw(tempdir);
use Test::More;

my $python = $ENV{PYTHON} // 'python3';
system( $python, '-c', 'import matplotlib, numpy' ) == 0
  or plan skip_all => 'matplotlib and numpy are required for plot smoke test';

my $tmp  = tempdir( CLEANUP => 1 );
my $limb = "$tmp/20260707_03_0335.limb";
my $plot = "$tmp/diagnostic.png";
open my $fh, '>', $limb or die "Cannot write $limb: $!";
print {$fh} "2040 2047 1900 0 2026-07-07T03:00:00Z 1900\n";
print {$fh} "2041 2046 1901 1 2026-07-07T03:01:00Z 1900\n";
print {$fh} "2042 2045 1902 2 2026-07-07T03:02:00Z 1900\n";
close $fh or die "Cannot close $limb: $!";

local $ENV{MPLCONFIGDIR} = "$tmp/matplotlib";
my $output = qx("$python" "$Bin/../plot_limb.py" "$limb" --perl=/bin/false -o "$plot" 2>&1);
is( $? >> 8, 0, 'plotter succeeds when reducer fails' ) or diag $output;
like( $output, qr{Reducer: FAILED}, 'plotter reports reducer failure' );
ok( -s $plot, 'plotter still writes diagnostic PNG' );

done_testing;
