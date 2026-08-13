use v5.38;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Temp qw(tempdir);
use Test::More;

use AIALimbfit::LimbfitCommand qw(
  limbfit_command
  limbfit_query
  plot_command
  run_limbfit_to_file
  wavelength_sum
);

is( wavelength_sum(94),   5, 'sum 5 below 1500A' );
is( wavelength_sum(1600), 3, 'sum 3 below 4000A' );
is( wavelength_sum(4500), 1, 'sum 1 for 4500A' );

is(
  limbfit_query(
    series     => 'aia.lev1',
    year       => 2026,
    month      => 5,
    day        => 1,
    hour       => 3,
    duration   => '3h',
    wavelength => 171,
    filter     => '[?MISSVALS<99?]',
  ),
  'aia.lev1[2026.05.01_03/3h][?WAVELNTH=171?][?MISSVALS<99?]',
  'limbfit query format'
);

is(
  limbfit_command(
    limbfit_exe => '/bin/limbfit',
    query       => q{series[2026.05.01_03/3h]},
    sum         => 5,
    outpath     => q{/tmp/out's.limb},
  ),
  q{/bin/limbfit dsinp='series[2026.05.01_03/3h]' sum=5 > '/tmp/out'"'"'s.limb'},
  'limbfit shell command'
);

is_deeply(
  [ plot_command( plotter => 'plot_limb.py', limb_path => '/tmp/a.limb' ) ],
  [ 'plot_limb.py', '/tmp/a.limb', '-o', '/tmp/a.png' ],
  'plot command argv'
);

my $tmp          = tempdir( CLEANUP => 1 );
my $fake_limbfit = "$tmp/fake_limbfit.pl";
open my $fake_fh, '>', $fake_limbfit or die "Cannot write $fake_limbfit: $!";
print {$fake_fh} "#!/usr/bin/env perl\n";
print {$fake_fh} "use v5.38;\n";
print {$fake_fh} "print qq{1 2\\n};\n";
print {$fake_fh} "exit 0;\n";
close $fake_fh or die "Cannot close $fake_limbfit: $!";
chmod 0755, $fake_limbfit or die "Cannot chmod $fake_limbfit: $!";

my $outpath = "$tmp/out.limb";
my $status  = run_limbfit_to_file(
  limbfit_exe => $fake_limbfit,
  query       => 'series[2026.05.01_03/3h]',
  sum         => 5,
  outpath     => $outpath,
);
is( $status, 0, 'run_limbfit_to_file returns child status' );
open my $out_fh, '<', $outpath or die "Cannot read $outpath: $!";
my $content = do { local $/; <$out_fh> };
close $out_fh or die "Cannot close $outpath: $!";
is( $content, "1 2\n", 'run_limbfit_to_file redirects child stdout into output file' );

done_testing;
