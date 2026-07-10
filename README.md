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

`update3h_mpt.pl` maps the centre time encoded in a masterpoint filename to the
slot's `T_START`/`T_STOP`, preserves newer DRMS records, and increments `VERSION`
when replacing an existing record.

### Example: one missing 3-hour slot

This report means the 03:00–06:00 UTC slot is absent:

```text
TEMPORAL GAP  2026-05-01T00:00:00Z  ->  2026-05-01T06:00:00Z  (6.00 h)
```

Preview and generate the repair for that day:

```console
./check_pointing_gaps.pl -repair -dry-run \
  -year=2026 -month=5 -day=1
./check_pointing_gaps.pl -repair \
  -year=2026 -month=5 -day=1
```

Inspect the `20260501_03_*.limb` files and PNGs under `$check_gaps_dir/limb/`,
then review `$check_gaps_dir/stage/masterpoint_20260501_0430_3hcadence.txt`.

### Example: one wavelength is NaN

This report means the 171 Å result failed in the 03:00–06:00 UTC slot:

```text
MISSING WAVELENGTHS  2026-05-01T03:00:00Z:  171
```

Use the same preview/repair sequence. Repair mode regenerates only the missing
wavelength, writes `20260501_03_0171.{limb,png}` under `$check_gaps_dir/limb/`,
atomically installs the regenerated `.limb` in `fits_root`, and stages the complete
slot masterpoint. Check its values before ingestion:

```console
rg 'A_171_[XY]0' \
  /surge40/nabil/LimbFit_c/gaps/stage/masterpoint_20260501_0430_3hcadence.txt
```

Repair mode handles every reported gap in the requested day or range. To commit
only this reviewed slot, copy it to a clean directory first:

```console
approved=$(mktemp -d)
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
approved=$(mktemp -d)
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

## Main files

| File | Purpose |
| --- | --- |
| `cron_submit_slot.pl` | Cadenced production entry point |
| `pipeline_slot_nrt.csh` | Three-stage production wrapper |
| `run_limbfit_ymdh.pl` | All- or single-wavelength limb fitting |
| `lf2mpr_nrt.pdl` | Limb reduction and masterpoint generation |
| `update3h_mpt.pl` | Reviewed masterpoint ingestion into DRMS |
| `check_pointing_gaps.pl` | Read-only reports and explicit repair staging |
| `lf_inv.pl` | Filesystem limb inventory |
| `plot_limb.py` | Raw diagnostics with real reducer status |

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
