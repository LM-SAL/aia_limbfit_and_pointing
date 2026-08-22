# AIA limb fitting at JSOC

This repository produces three-hour `aia.master_pointing3h` records from AIA
Level-1 images.

## Production

`cron_submit_slot.pl` is the only production entry point. For one slot it runs:

```text
run_limbfit_ymdh.pl -> lf2mpr_nrt.pdl -> update3h_mpt.pl
```

A slot succeeds only when every configured wavelength produces a non-empty limb
file and a finite reduced center. A missing input, invalid fit, split cluster, or
non-finite center stops the slot before publication. The cron driver writes one
log and sends one failure email containing its tail.

Runtime values live in `config.pl`. `config.csh` only bootstraps an interactive
JSOC C-shell.

The fitter targets data 22 hours behind the invocation time. The hourly cron is
safe: the driver silently skips hours that do not map to the 00/03/06/... data
grid, so cron email is reserved for real failures:

```cron
1 * * * * /homef/nabil/Git/aia_limbfit_and_pointing/cron_submit_slot.pl
```

Preview or run one slot:

```console
./cron_submit_slot.pl -dry-run -year=2026 -month=3 -day=28 -hour=0
./cron_submit_slot.pl          -year=2026 -month=3 -day=28 -hour=0
```

For one diagnostic wavelength, output defaults to the backfill workspace and a
PNG is generated:

```console
./run_limbfit_ymdh.pl -year=2026 -month=3 -day=28 -hour=0 -wavel=171
```

## Backfill report

`check_pointing_gaps.pl` is read-only. It reports missing pointing slots and NaN
wavelengths, examines any existing limb file with the production reducer, and
prints isolated commands for each affected slot. It does not create files or
change DRMS.

```console
# Mission report through seven days ago
./check_pointing_gaps.pl

# One day or range
./check_pointing_gaps.pl -year=2024 -month=3 -day=1
./check_pointing_gaps.pl \
  -year=2024 -month=3 -day=1 \
  -end_year=2024 -end_month=6 -end_day=1
```

Slots older than the configured 14-day NRT retention window automatically use
`aia.lev1`; recent slots use `aia.lev1_nrt2`. Override the image source only
when needed:

```console
./check_pointing_gaps.pl -year=2024 -month=3 -day=1 -image-series=aia.lev1
```

The report prints a per-slot sequence equivalent to:

```console
./run_limbfit_ymdh.pl ... -outroot=/surge40/nabil/LimbFit_c/gaps/SLOT/limb
./lf2mpr_nrt.pdl ... \
  -inpdir=/surge40/nabil/LimbFit_c/gaps/SLOT/limb \
  -outdir=/surge40/nabil/LimbFit_c/gaps/SLOT/stage
./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/SLOT/stage -dry-run
```

Inspect the limb files, diagnostic plots, reducer output, and publication dry
run. Publish only by rerunning the final command without `-dry-run`.

If both bracketing pointing records exist, the report also prints an explicit
`-interpolate-previous=... -interpolate-next=...` fallback. Use it instead of
the normal reducer only after deciding the regenerated limb fit is physically
bad. It linearly interpolates every wavelength at the target time and refuses
missing or non-finite endpoints; it never extrapolates.

For a wavelength gap in an existing DRMS row, `lf2mpr_nrt.pdl -wavel=1700`
creates a partial repair from that limb file alone. `update3h_mpt.pl` refuses a
partial repair if the target row is absent; otherwise it preserves every other
value from the existing row. Production does not pass `-wavel` and remains
complete/all-or-fail. Repeat `-wavel` to repair several wavelengths together.
The gap checker prints this shorter route when every missing wavelength already
has a usable limb file.

Newly published records provisionally span six hours. When the adjacent row is
published, `update3h_mpt.pl` shortens the previous record to three hours. The gap
checker accepts any cadence-aligned covered block—including 6 or 24 hours—when
the previous `T_STOP` reaches the later `T_START`.

## Split clusters

The reducer looks for one temporal break leaving two sufficiently populated
segments whose centers are widely separated relative to their internal scatter.
It reports the cut directly:

```text
Split-cluster detected (94A): split after row 88, segments 88/92, separation/scatter 29.9
```

The backfill report prints both candidate commands. Plot the regenerated file,
choose the physically valid segment, run exactly one cut, then reduce again:

```console
./plot_limb.py /path/to/20260326_18_0094.limb

# Keep the first segment
head -n 88 /path/to/20260326_18_0094.limb > /tmp/94.keep

# Or keep the second segment
tail -n +89 /path/to/20260326_18_0094.limb > /tmp/94.keep
```

Replace only the copy in the isolated backfill workspace. Production limb files
are not edited by the report. The reducer will not emit a partial or NaN
masterpoint.

With the limb file trimmed to one segment, reduce it, inspect the dry run, then
publish:

```console
./lf2mpr_nrt.pdl -year=2026 -month=3 -day=26 -hour=18 \
  -inpdir=/surge40/nabil/LimbFit_c/gaps/20260326_18/limb \
  -outdir=/surge40/nabil/LimbFit_c/gaps/20260326_18/stage
./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/20260326_18/stage -dry-run
./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/20260326_18/stage
```

If only one wavelength split and the DRMS row already exists, repair just that
wavelength with `-wavel`. With a production limb file, `-inpdir` is the
`fits_root` and the reducer builds the dated path itself:

```console
./lf2mpr_nrt.pdl -year=2026 -month=8 -day=20 -hour=9 -wavel=1600 \
  -inpdir=/surge40/nabil/LimbFit_c/fits_nrt \
  -outdir=/surge40/nabil/LimbFit_c/gaps/20260820_09/stage
./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/20260820_09/stage -dry-run
./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/20260820_09/stage
```

Two calibration values remain in `config.pl` because real sensor data varies:
minimum useful segment size and required center-separation/scatter ratio.

## Invalid Level-1 geometry

After a native fitter failure, inspect the exact bounded input set:

```console
source config.csh
./scan_lev1_geometry.pl \
  -ds='aia.lev1[2026.03.26_18/3h][?WAVELNTH=94?]'
```

The scanner reports records whose `R_SUN`, `CRPIX1`, or `CRPIX2` are not finite
and positive, or whose `CRVAL1`/`CRVAL2` are not finite. Repair or exclude the
source data; do not synthesize a replacement center.

## Diagnostic plots

`plot_limb.py` plots X/Y centers, radius by sample, and center scatter:

```console
./plot_limb.py data/20260326_18_0094.limb -o /tmp/diagnostic.png
```

It requires NumPy and Matplotlib. Reduction and its exact failure reason remain
in Perl so the plotter does not duplicate production rules.

## Development

The pipeline requires Perl 5.38 or newer and PDL. Formatting and linting use
Perl::Tidy, Perl::Critic, and Ruff.

```console
prove -lv t
./tools/format-perl.sh
./tools/lint-perl.sh
ruff check plot_limb.py
csh -n config.csh
```
