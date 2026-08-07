# AIA limb fitting at the JSOC

This repository runs the [Atmospheric Imaging Assembly (AIA)](https://aia.lmsal.com/)
limb-fit pipeline at the
[Joint Science Operations Center (JSOC)](http://jsoc.stanford.edu/). It produces
3-hour master-pointing records in `aia.master_pointing3h`.

Originally written by [John Serafin](mailto:jps@lmsal.com).

## Production pipeline

```text
cron_submit_slot.pl
└─ pipeline_slot_nrt.csh
   ├─ run_limbfit_ymdh.pl  → .limb files
   ├─ lf2mpr_nrt.pdl       → masterpoint_*.txt
   └─ update3h_mpt.pl      → aia.master_pointing3h
```

Deployment paths, DRMS series, wavelengths, and reducer thresholds live in
`config.pl`; the C-shell environment lives in `config.csh`. Edit those two files
when moving the pipeline.

> JSOC interactive sessions use `csh` by default, not Bash. The examples below
> use C-shell assignments such as “set work = \`mktemp -d\`”; use `work=$(mktemp -d)`
> only when you have explicitly started Bash.

The production cron entry on `solar4` runs hourly and acts every three hours:

```cron
1 * * * * /homef/nabil/Git/aia_limbfit_and_pointing/cron_submit_slot.pl
```

The default slot begins 22 hours before invocation. Process a specific slot with
either entry point:

```console
./cron_submit_slot.pl -year=2026 -month=3 -day=28 -hour=0
./pipeline_slot_nrt.csh 2026 3 28 0
```

Run one wavelength for diagnosis without invoking the full pipeline:

```console
./run_limbfit_ymdh.pl -year=2026 -month=3 -day=28 -hour=0 -wavel=171
```

Single-wavelength runs default to `aia.lev1`, `test_fits_root`, and a diagnostic
plot. All-wavelength runs default to `lev1_series`, `fits_root`, and no plots.
Use `-series`, `-outroot`, and `-plots`/`-no-plots` to override those defaults.

## Invalid Level-1 geometry

`R_SUN`, `CRPIX1`, and `CRPIX2` must all be finite and positive before the
native fitter can locate a limb. Scan a bounded Level-1 record set before a
repair or after a fitter failure:

```console
source config.csh

# One wavelength in a 3-hour pointing window
./scan_lev1_geometry.pl \
  -ds='aia.lev1[2026.03.26_18/3h][?WAVELNTH=94?]'

# All wavelengths in the same window
./scan_lev1_geometry.pl -ds='aia.lev1[2026.03.26_18/3h]'
```

The scanner prints the FSN, observation time, wavelength, values, and invalid
fields; it exits 1 if it finds any. It queries all records in the supplied
record set and checks them locally: do not replace this with a DRMS `> 0`
predicate, because PostgreSQL's `NaN` compares greater than ordinary numbers.

### Hardening the JSOC executable

An unpatched `limbfit_aia` can segfault when a Level-1 record has invalid
geometry or no limb-annulus candidates. The native patch in
[`patches/limbfit_aia_invalid_geometry.patch`](patches/limbfit_aia_invalid_geometry.patch)
makes `limbcompute()` reject those cases and makes the application log and skip
the failed five-image sum. It does not repair missing pointing metadata or
create a limb fit from invalid input.

Apply the patch in a JSOC source checkout, then rebuild and install the
configured executable. These are C-shell commands for `solar4`:

```console
cd ~/Git/JSOC-orig
git switch -c fix/limbfit-invalid-geometry
git apply ~/Git/aia_limbfit_and_pointing/patches/limbfit_aia_invalid_geometry.patch

source build/oneapi.csh
make limbfit_aia
make install

# config.pl uses this executable; the diagnostic string confirms the install.
strings bin/linux_avx2/limbfit_aia | rg 'invalid limb geometry'
```

If the branch already exists, use `git switch fix/limbfit-invalid-geometry`
instead of creating it. Keep the source change on its own branch for upstream
review; `config.pl` points this pipeline at
`/homef/nabil/JSOC-orig/bin/linux_avx2/limbfit_aia`.

## Historical gap workflow

Gap reports are read-only: they query DRMS and write a wavelength report to
`$check_gaps_dir/patch.txt`, but never run limb fits or modify production data.

```console
# Full historical report: 2010-11-01 through seven days ago
./check_pointing_gaps.pl

# One day or an explicit range
./check_pointing_gaps.pl -year=2024 -month=3 -day=1
./check_pointing_gaps.pl \
  -year=2024 -month=3 -day=1 \
  -end_year=2024 -end_month=6 -end_day=1
```

Repairs require an explicit start date. Review the report, preview the commands,
then generate only the approved date or range:

```console
# Preview: no limb files are changed
./check_pointing_gaps.pl -repair -dry-run \
  -year=2024 -month=3 -day=1

# Generate limb files, diagnostic plots, and staged masterpoints
./check_pointing_gaps.pl -repair \
  -year=2024 -month=3 -day=1
```

For old data, add `-image_series=aia.lev1`. Repair mode may atomically replace a
regenerated wavelength under `fits_root`, but it does not write DRMS. Inspect the
limb files, plots, and `$check_gaps_dir/stage/masterpoint_*.txt`. Copy only approved
masterpoints to a clean directory before invoking `update3h_mpt.pl`, as shown below.

`update3h_mpt.pl` maps the centre time encoded in a masterpoint filename to a
3-hour-cadence row. A newly published row provisionally covers 6 hours; once the
adjacent next row is present, the earlier row is shortened to its normal 3-hour
span. Newer DRMS records are preserved, and `VERSION` is incremented when an
existing record is replaced.

### Gap examples

This report means the 03:00–06:00 UTC slot is absent. Run the preview/repair
sequence above with `-year=2026 -month=5 -day=1`, then inspect the generated
`20260501_03_*.{limb,png}` files and staged masterpoint.

```text
TEMPORAL GAP  2026-05-01T00:00:00Z  ->  2026-05-01T06:00:00Z  (6.00 h)
```

This report means only 171 Å failed in that slot. The same repair sequence
regenerates `20260501_03_0171.{limb,png}`, installs the reviewed `.limb`, and
stages a complete masterpoint.

```text
MISSING WAVELENGTHS  2026-05-01T03:00:00Z:  171
```

```console
rg 'A_171_[XY]0' \
  /surge40/nabil/LimbFit_c/gaps/stage/masterpoint_20260501_0430_3hcadence.txt
```

For either case, copy only the reviewed masterpoint before ingestion:

```console
set approved = `mktemp -d`
cp /surge40/nabil/LimbFit_c/gaps/stage/masterpoint_20260501_0430_3hcadence.txt \
  "$approved/"
./update3h_mpt.pl -srcdir="$approved" -dry-run
./update3h_mpt.pl -srcdir="$approved"
```

### Mission-wide audit and batch backfill

The no-argument report scans the pointing series from 2010-11-01 through seven
days ago. Save its temporal and wavelength-gap output for review:

```console
./check_pointing_gaps.pl | tee /tmp/aia_pointing_gaps.txt
```

This does not run limb fitting or change DRMS. Once the report is approved,
generate pointing files in bounded batches rather than repairing the whole
mission at once. For example, preview and process November 2010 with `aia.lev1`:

```console
./check_pointing_gaps.pl -repair -dry-run -image_series=aia.lev1 \
  -year=2010 -month=11 -day=1 \
  -end_year=2010 -end_month=11 -end_day=30

./check_pointing_gaps.pl -repair -image_series=aia.lev1 \
  -year=2010 -month=11 -day=1 \
  -end_year=2010 -end_month=11 -end_day=30
```

The generated pointing files are under `$check_gaps_dir/stage/`. Stop there if
the goal is only to build missing masterpoints. To fill DRMS, isolate and inspect
the approved batch before ingestion:

```console
set approved = `mktemp -d`
cp /surge40/nabil/LimbFit_c/gaps/stage/masterpoint_201011*.txt "$approved/"
rg '^KWD ' "$approved"
./update3h_mpt.pl -srcdir="$approved" -dry-run
./update3h_mpt.pl -srcdir="$approved"
```

Repeat for the next month or another reviewed range. `update3h_mpt.pl` processes
every masterpoint in its source directory, so never use a mixed staging directory
unless every file in it has been approved.

To regenerate plots for existing gap-work files without repairing anything:

```console
./check_pointing_gaps.pl -plots -year=2024 -month=3 -day=1
```

For filesystem-only inventory, use `lf_inv.pl`:

```console
./lf_inv.pl
./lf_inv.pl -year=2024 -month=3 -fits_root=/other/path
```

## Reduction and recovery

`lf2mpr_nrt.pdl` reduces all configured wavelengths for one slot using two-pass
sigma clipping. It filters the 4500 Å sentinel, rejects obvious split clusters,
and writes files atomically. If one wavelength fails, it writes `NaN` for that
wavelength and continues; `-require-all` rejects missing input files.

```console
./lf2mpr_nrt.pdl \
  -inpdir=/path/to/fits -outdir=/tmp/masterpoints \
  -year=2024 -month=3 -day=28 -hour=0 -require-all
```

Reducer thresholds and split-cluster detection remain configurable in `config.pl`.
For an operator-approved value after a reducer failure, supply a validated override:

```text
# wavelength  x_center  y_center
335 2040.554 2046.711556
```

```console
./lf2mpr_nrt.pdl ... -override-file=/path/to/overrides.txt
```

Overrides are accepted only for failed/non-finite wavelengths; invalid, duplicate,
unconfigured, and unused entries are rejected.

`suggest_nan_overrides.pl` turns missing masterpoint values into reviewable override
files using neighboring masterpoints and, when available, radius-consistent limb
samples:

```console
./suggest_nan_overrides.pl \
  -srcdir=/surge40/nabil/LimbFit_c/mpt3h \
  -fits-root=/surge40/nabil/LimbFit_c/fits_nrt \
  -outdir=/tmp/limbfit-overrides
```

`HIGH` means limb and temporal evidence agree. A conflict still emits a
`REVIEW_REQUIRED` best guess: it prefers the direct limb candidate; if the target
limb is unavailable, it uses the bounded temporal candidate. The output file is
reducer-compatible but is never applied automatically. `UNRESOLVED` is reserved
for cases without two sufficiently close trusted anchors, where the tool has no
defensible numeric estimate.

For example, a conflict still produces an actionable file:

```text
CONFLICT masterpoint_20260707_0430_3hcadence.txt 335 ...
BEST_GUESS masterpoint_20260707_0430_3hcadence.txt 335 2040.554000 2046.711556 ... confidence=REVIEW_REQUIRED
```

For one reviewed failure, copy the masterpoint, edit only the failed wavelength
using that override, inspect the diff, and preview ingestion:

```console
set name = masterpoint_20260707_0430_3hcadence.txt
set srcdir = /surge40/nabil/LimbFit_c/mpt3h
set approved = `mktemp -d`

cp "$srcdir/$name" "$approved/$name"
cat ./masterpoint_20260707_0430_3hcadence.overrides.txt
if ($?EDITOR) then
  $EDITOR "$approved/$name"
else
  vi "$approved/$name"
endif

diff -u "$srcdir/$name" "$approved/$name"
rg 'A_335_[XY]0' "$approved/$name"
./update3h_mpt.pl -srcdir="$approved" -dry-run
# Only after approving the two changed values:
./update3h_mpt.pl -srcdir="$approved"
```

When every source limb exists, the reproducible alternative is to regenerate the
slot with the same override, then inspect `$work` and pass it to
`update3h_mpt.pl -dry-run` before publishing:

```console
set work = `mktemp -d`
./lf2mpr_nrt.pdl \
  -inpdir=/surge40/nabil/LimbFit_c/fits_nrt \
  -outdir="$work" \
  -year=2026 -month=7 -day=7 -hour=3 \
  -require-all \
  -override-file=./masterpoint_20260707_0430_3hcadence.overrides.txt
```

If the wavelength is absent because its source limb file is missing, do not
regenerate the masterpoint: the reducer cannot consume an override without that
input. For `masterpoint_20260610_1930_3hcadence.txt`, copy the file as above and
add only:

```text
KWD A_1600_X0	2049.983532
KWD A_1600_Y0	2049.797014
```

After the diff, dry-run, and publish steps, confirm the 18:00 slot in DRMS
(`aia_mpt_day 2026.06.10` if that local alias is installed):

```console
show_info 'key=T_START,T_STOP,A_1600_X0,A_1600_Y0' \
  'aia.master_pointing3h[2026.06.10/1d]' | column -t
```

### Split clusters

When the reducer reports two separated temporal clusters, inspect the diagnostic
plot and keep only the physically valid segment. For the included 94 Å example:

```console
# Keep the first segment; use tail -n +89 for the second
head -n 88 data/20260326_18_0094.limb > /tmp/20260326_18_0094.limb

mkdir -p /tmp/splitfix/in/2026/03/26 /tmp/splitfix/out
cp /tmp/20260326_18_0094.limb \
  /tmp/splitfix/in/2026/03/26/20260326_18_0094.limb

./lf2mpr_nrt.pdl \
  -year=2026 -month=3 -day=26 -hour=18 \
  -inpdir=/tmp/splitfix/in -outdir=/tmp/splitfix/out
```

Inspect the resulting masterpoint before passing it to `update3h_mpt.pl`. The
original production `.limb` file remains unchanged.

## Diagnostic plots

`plot_limb.py` plots raw X/Y centres, radius, and centre scatter. It invokes the
real reducer and annotates the PNG with its final centre or exact failure reason;
it does not reimplement reducer logic.

```console
./plot_limb.py data/20260707_03_0335.limb -o /tmp/diagnostic.png
./plot_limb.py data/20260707_03_0335.limb --no-reducer
```

It requires NumPy and Matplotlib. Use `--perl=/path/to/perl` outside the deployed
JSOC environment.

## Development

The pipeline requires Perl 5.42, PDL, and `PDL::Stats`. Formatting and linting
also use `Perl::Tidy` and `Perl::Critic`.

```console
perlbrew install perl-5.42.0
perlbrew switch perl-5.42.0
cpanm PDL PDL::Stats Perl::Tidy Perl::Critic

prove -lv t
./tools/format-perl.sh
./tools/lint-perl.sh
csh -n config.csh pipeline_slot_nrt.csh
```

Tests can inject temporary paths and fake executables with
`AIA_LIMBFIT_CONFIG=/path/to/config.pl`. GitHub Actions runs the Perl suite;
pre-commit runs Ruff and lightweight repository checks.
