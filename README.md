# AIA limb fitting at the JSOC

## Overview

This document describes the code used in the [Atmospheric Imaging Assembly (AIA)](https://aia.lmsal.com/) limb fit pipeline at the [Joint Science Operations Center (JSOC)](http://jsoc.stanford.edu/) - Science Data Processing (SDP).
The active production path is the C-based near-real-time limb-fit pipeline plus the Perl/PDL reduction and DRMS update scripts that follow it.

Shared deployment paths, environment settings, binary paths, and pipeline constants are centralized in `config.pl` (loaded by the Perl scripts) and `config.csh` (sourced by the C shell wrapper).
To redeploy to a different machine or storage volume, edit only those two files.

Originally this was all written by [John Serafin](mailto:jps@lmsal.com).

These are the user-facing scripts in the current repo root and `tools/` folder.

| Script | Purpose |
| ------ | ------- |
| `cron_submit_slot.pl` | Run the production 3-hour C pipeline directly on solar4. |
| `pipeline_slot_nrt.csh` | Run the full 3-stage NRT C pipeline directly. |
| `run_limbfit_ymdh.pl` | Run `limbfit_aia` for one 3-hour slot across all wavelengths. |
| `run_limbfit_test.pl` | Run a single-wavelength debug fit against `aia.lev1` into the test output tree. |
| `plot_limb.py` | Diagnostic plotter for raw `.limb` files (run manually). |
| `lf2mpr_nrt.pdl` | Reduce `.limb` files into `masterpoint_*.txt`. |
| `update3h_mpt.pl` | Merge `masterpoint_*.txt` into `aia.master_pointing3h` in DRMS. |
| `update_nans.pl` | Patch a bad `.limb`, re-reduce it, and write the repaired master-pointing record. |
| `check_pointing_gaps.pl` | Query `aia.master_pointing3h` in DRMS and report temporal gaps and missing wavelengths. |
| `lf_inv.pl` | Scan for missing `.limb` files. |
| `tools/lint-perl.sh` | Syntax-check and lint tracked Perl / PDL scripts. |
| `tools/format-perl.sh` | Format tracked Perl / PDL scripts with `perltidy`. |
| `tools/lint-csh.sh` | Syntax-check tracked C shell scripts. |
| `tools/format-csh.sh` | Format tracked C shell scripts conservatively. |
| `config.csh` | Sourceable C shell configuration shared by the wrapper script. |

## Linting and formatting

Under the `tools` folder are four scripts, two each for Perl and C shell scripts.

```console
    ./tools/format-csh.sh
    ./tools/lint-csh.sh
    ./tools/format-perl.sh
    ./tools/lint-perl.sh
```

`tools/lint-perl.sh` lints all tracked `*.pl` and `*.pdl` files by default.
`tools/format-perl.sh` runs `perltidy` with the repo's `.perltidyrc` and it formats all tracked `*.pl` and `*.pdl` files.

`tools/lint-csh.sh` uses `csh -n` to syntax-check tracked `*.csh` files.
`tools/format-csh.sh` is a conservative repo-local formatter for `*.csh`.

These require a Perl install with both `Perl::Tidy` and `Perl::Critic` modules installed.

## Testing

Perl unit tests live in `t/` and use the standard `Test::More` / `prove` workflow:

```console
    prove -lv t
```

The tests cover the shared modules under `lib/AIALimbfit/`, including slot timestamp mapping, reducer edge cases, limbfit command construction, gap inventory path generation, NaN patch command construction, and cron slot command generation. They also include script-level checks for dry-run command generation, fake-DRMS gap detection, and `lf2mpr_nrt.pdl` masterpoint output. Reducer tests require the same PDL install used by the pipeline.

Most Perl scripts honor `AIA_LIMBFIT_CONFIG=/path/to/config.pl`, which lets tests inject temporary paths and fake executables. Command wrappers that would normally call production tools also provide `-dry-run` where practical, so local tests can assert the generated commands without touching DRMS, SGE, `limbfit_aia`, or production data trees.

GitHub Actions runs the same `prove -lv t` suite on pushes and pull requests. A `.pre-commit-config.yaml` is also included for local Python checks with Ruff linting/formatting plus common lightweight hygiene hooks; it intentionally avoids Perl and csh hooks.

## Installing Perl

On JSOC, the local Perl install is old, so it is ideal to install a local version with `PDL` and `PDL::Stats`.
To do this, `perlbrew` is the simplest way:

```console
    curl -L https://install.perlbrew.pl | bash
    source ~/perl5/perlbrew/etc/cshrc  # Or the bashrc if you use bash but by default csh is used at the JSOC.
    perlbrew install perl-5.42.0  # Latest version at time of writing
    perlbrew switch perl-5.42.0
    cpanm PDL PDL::Stats # Perl::Tidy Perl::Critic
```

## crontab Entries

```console
    1 * * * * /homef/nabil/Git/aia_limbfit_and_pointing/cron_submit_slot.pl
```

The above crontab listing is for user `nabil` on `solar4` at the Stanford JSOC-SDP.
If you are deploying this, you will need to point the path to your git clone.

The `cron_submit_slot.pl` script runs the active C-based limb-fit flow directly on solar4. |
It is started once per hour, but it exits immediately if the UTC hour modulo 3 is not 0.
By default the start time for the sequence is 22 hours before the hour the script is called.

The Perl script takes optional arguments to set year, month, day, and hour for the 3 hour interval of images to be limb fit.
These can be used interactively to fill gaps when the cron job did not run or complete.
In addition to limb fitting the images, the wrapper scripts call the shared reduction and update scripts that calculate master pointing table entries and write them to the [Data Record Management System (DRMS)](http://jsoc.stanford.edu/jsocwiki/DataSeries).

An example interactive invocation is

```console
    /homef/nabil/Git/aia_limbfit_and_pointing/cron_submit_slot.pl -y=2026 -mo=3 -d=28 -h=0
```

for limb fitting with C.

If you want to run the full near-real-time C shell wrapper directly instead of the Perl cron submitter, use `pipeline_slot_nrt.csh` with positional arguments `year month day hour`:

```console
    /homef/nabil/Git/aia_limbfit_and_pointing/pipeline_slot_nrt.csh 2026 3 28 0
```

## Limb Fit Data Flow

The active C data flow updates the DRMS series `aia.master_pointing3h`.

### C Data Flow

Since the C based AIA limb fitting is implemented as a DRMS module, it has direct access to DRMS services and needs fewer support scripts.
The `pipeline_slot_nrt.csh` wrapper calls `run_limbfit_ymdh.pl`, which invokes the `limbfit_aia module` using a DRMS query string specifying the series, time range, and other constraints for the images to have limb fits.
The `limbfit_aia module` also has an option to sum multiple images to improve the limb definition before fitting.
`run_limbfit_ymdh.pl` sets a custom number of images to be summed based on image wavelength.
The computed limb fits are stored under `fits_root` from `config.pl`, using the same date based directory and file name structure consumed by the shared post-processing tools.
Next, `lf2mpr_nrt.pdl` reduces the `.limb` files into a single `masterpoint_YYYYMMDD_HHMM_3hcadence.txt` output and `update3h_mpt.pl` merges that output with metadata from `sdo.master_pointing` before writing the target DRMS series.

## Execution Order & Workflow

### Production Pipeline (Automated)

The normal 3-hour production flow runs automatically via cron and consists of three stages:

```text
1. cron_submit_slot.pl (cron entry point)
   ├─ Runs hourly, acts every 3 hours if UTC hour % 3 == 0
   ├─ Default target: 3-hour slot ending ~19 hours ago
   └─ Runs directly on solar4

2. pipeline_slot_nrt.csh (pipeline orchestrator)
   ├─ Stage 1: run_limbfit_ymdh.pl
   │   └─ Output: .limb files and .png diagnostic plots (one per wavelength)
   ├─ Stage 2: lf2mpr_nrt.pdl
   │   └─ Output: masterpoint_YYYYMMDD_HHMM_3hcadence.txt
   └─ Stage 3: update3h_mpt.pl
       └─ Output: aia.master_pointing3h DRMS record
```

### Interactive / Backfill Runs

To process a specific 3-hour slot manually:

```console
    # Via cron wrapper (runs directly on solar4):
    ./cron_submit_slot.pl -y=2026 -mo=3 -d=28 -h=0

    # Or run wrapper directly (immediate execution):
    ./pipeline_slot_nrt.csh 2026 3 28 0
```

The Perl scripts use `Getopt::Long`, so argument names may be supplied in any order, names and values can be separated by `'='` or `' '`, and names can be abbreviated (e.g. `-y` for `-year`).

To debug a single wavelength without triggering the full pipeline:

```console
    ./run_limbfit_test.pl -y=2024 -mo=3 -da=28 -h=0 -wavel=171
```

### Gap Detection and Recovery

#### Finding Missing Data

**DRMS-level gap check:** Use `check_pointing_gaps.pl` to query the pointing table directly for temporal gaps and missing wavelengths:

```console
    # Scan from 2010-11-01 to 7 days ago:
    ./check_pointing_gaps.pl

    # Scan a specific range:
    ./check_pointing_gaps.pl -year=2024 -month=3 -day=1 -end_year=2024 -end_month=6 -end_day=1

    # For gaps before 2022-06-08, aia.lev1 is selected automatically;
    # pass -image_series=aia.lev1 to force it for all slots:
    ./check_pointing_gaps.pl -image_series=aia.lev1

    # Only regenerate plots for existing .limb files:
    ./check_pointing_gaps.pl -plots

    # Commit temporal gaps to DRMS:
    ./update3h_mpt.pl -srcdir=/surge40/nabil/LimbFit_c/gaps/stage

    # Commit wavelength gaps to DRMS:
    cat /surge40/nabil/LimbFit_c/gaps/patch.txt | ./update_nans.pl
```

**Filesystem-level gap check:** Use `lf_inv.pl` to scan for missing `.limb` files:

```console
    # Scan from 2017-01-01 to ~24 hours ago:
    ./lf_inv.pl

    # Scan from a specific date:
    ./lf_inv.pl -year=2024 -month=3

    # Use a custom fits directory:
    ./lf_inv.pl -fits_root=/other/path
```

Each missing file is reported as:

```console
/path/to/fits_root/YYYY/MM/DD/YYYYMMDD_HH_WWWW.limb missing
```

#### Filling Gaps

**For recent gaps:** Re-run the normal pipeline for that slot—`aia.lev1_nrt2` should still have the data:

```console
    ./cron_submit_slot.pl -y=2024 -mo=3 -d=28 -h=0
```

**For old gaps** (data only in `aia.lev1`, not `lev1_nrt2`): Use `update_nans.pl` to patch and re-reduce:

1. Create or obtain a gap-fill `.limb` file:

```console
    ./run_limbfit_ymdh.pl -y=2024 -mo=3 -d=28 -h=0 -series=aia.lev1
```

2. Prepare an input file with records in the form:

```console
YYYY-MM-DDTHH:MM:SSZ  wavelength  x_centre  y_centre
2024-03-28T00:00:00Z  171  960.5  1024.3
```

3. Back-fill via `update_nans.pl`:

```console
    grep ^2024 aia.master_pointing3h_miss.171 | /homef/nabil/Git/aia_limbfit_and_pointing/update_nans.pl
```

The script will:

- Locate the corresponding `.limb` file
- Patch it in-place with the NaN sed script
- Re-reduce through `lf2mpr_nrt.pdl`
- Commit the corrected result via `update3h_mpt.pl`

#### Split-Cluster Remediation

`lf2mpr_nrt.pdl` refuses to average a `.limb` file that contains two well-separated temporal clusters.
When this happens the reducer dies with a message like:

```console
Split-cluster detected for .../20260326_18_0094.limb (94A);
  refusing to average across two temporal segments.
```

To recover and commit one of the segments (production `.limb` files live under `$fits_root/YYYY/MM/DD/`; the `data/` path below is just the local sample copy):

1. **Identify the split index** from the reducer output (e.g. `split after sample 88`).

2. **Create a trimmed `.limb`** containing only the segment you want to keep:

```console
# Keep the first segment (lines 1-88)
head -n 88 data/20260326_18_0094.limb > /tmp/20260326_18_0094_seg1.limb

# Or keep the second segment (lines 89-end)
tail -n +89 data/20260326_18_0094.limb > /tmp/20260326_18_0094_seg2.limb
```

3. **Re-run the reducer** on the trimmed file in a temp tree:

```console
mkdir -p /tmp/splitfix/in/2026/03/26
mkdir -p /tmp/splitfix/out
mkdir -p /tmp/splitfix/stage

cp /tmp/20260326_18_0094_seg1.limb \
   /tmp/splitfix/in/2026/03/26/20260326_18_0094.limb

perl lf2mpr_nrt.pdl \
  -year=2026 -month=3 -day=26 -hour=18 \
  -inpdir=/tmp/splitfix/in -outdir=/tmp/splitfix/out
```

4. **Commit to DRMS** via `update3h_mpt.pl`:

```console
cp /tmp/splitfix/out/masterpoint_*.txt /tmp/splitfix/stage/
./update3h_mpt.pl -srcdir=/tmp/splitfix/stage
```

The original `.limb` remains unchanged in `fits_root`.

#### Decision Matrix

| Question | Answer | Script |
| -------- | ------ | ------ |
| Process new 3-hour window? | Run directly on solar4 | `cron_submit_slot.pl` |
| | Run directly (immediate) | `pipeline_slot_nrt.csh` |
| Debug single wavelength? | Yes | `run_limbfit_test.pl -wavel=XXX` |
| Have .limb files, need master-pointing? | Yes | `lf2mpr_nrt.pdl -inpdir=... -outdir=...` |
| Have master-pointing, need DRMS? | Yes | `update3h_mpt.pl -srcdir=...` |
| Looking for DRMS pointing gaps? | Yes | `check_pointing_gaps.pl` |
| Looking for missing files? | Yes | `lf_inv.pl` |
| Repairing NaN/missing entries? | Old gaps | `update_nans.pl < input.txt` |
| Split cluster in a .limb file? | Trim and re-reduce | See Split-Cluster Remediation above |

## Script Notes

### config.pl / config.csh

`config.pl` is a plain Perl file that returns a hashref of all shared values for the NRT pipeline: AIA wavelengths, JSOC/SGE environment, binary paths, DRMS series names, deployment data paths, and pipeline constants.
Each Perl script loads it with:

```perl
my $cfg = do "$FindBin::RealBin/config.pl" or die 'Cannot load config.pl: ' . ($@ || $!);
```

Key entries in the hashref include:

- `fits_root` (where production `.limb` files are written)
- `test_fits_root` (default output tree for `run_limbfit_test.pl`)
- `pointing_dir` (default stage directory for `lf2mpr_nrt.pdl` and default source directory for `update3h_mpt.pl`; production flow overrides both via command-line arguments)
- `lev1_series`, `lev1_nrt2_start`, `drms_filter` (NRT DRMS query components; `lev1_nrt2_start` is the ISO-8601 epoch before which slots fall back to `aia.lev1`)
- `limbfit_exe` (path to the `limbfit_aia` binary)
- `mpt_series` / `sdo_series` (DRMS target and attitude reference series)
- `wl` (wavelength list)
- `cadence_h` (3)
- `sigma_clip_pass1_baseline` / `sigma_clip_pass2_baseline` (`zero` for the historical `N * sigma` cutoff, `mean` for `mean(distance) + N * sigma`)
- `sigma_clip_pass1_sigma` / `sigma_clip_pass2_sigma` (sigma multipliers for the two reduction passes)
- `split_cluster_mode` (`fail` to abort on obvious two-cluster files, `ignore` to disable that safeguard)
- `split_cluster_min_segment_size`, `split_cluster_jump_sigma`, `split_cluster_jump_ratio`, `split_cluster_separation_ratio` (thresholds for the split-cluster detector)
- `nan_sentinel` (1234567 — the placeholder written by `limbfit_aia` for 4500 Å),
- `mail_to` (address for NaN alerts)
- `check_gaps_dir` (default output directory for `check_pointing_gaps.pl`)
- `update_dir` (scratch directory for `update_nans.pl` reductions)
- `lf_sed` (path to the machine-local sed script used for NaN patching)

`config.csh` is sourced by `pipeline_slot_nrt.csh` near its top and exposes the same deployment paths as csh variables (`$REPO_ROOT`, `$FITS_ROOT`, `$MPT_DIR`, `$STAGE_DIR`) plus `SUMSERVER` and `TZ` environment variables.

**Directories:** Each script creates its output directories automatically on first run. You do not need to pre-create them before launching the pipeline.

To redeploy to a different machine or storage volume, edit only these two files.

### cron_submit_slot.pl

The production cron entrypoint.
Runs every hour; exits immediately if the UTC hour modulo 3 is not 0.
When it does run it executes `pipeline_slot_nrt.csh` directly on solar4.
The default target interval is the 3-hour window that began 22 hours before the current UTC hour (i.e., the most recent complete 3-hour slot that ended roughly 19 hours ago).

Log and error output go to `$logs_dir/YYYYMMDD_HH.{log,err}`.
On the current deployment this resolves to `/surge40/nabil/LimbFit_c/logs_nrt/YYYYMMDD_HH.{log,err}`.

```console
    # crontab entry on solar4 (runs every hour, acts every 3 h):
    1 * * * * /homef/nabil/Git/aia_limbfit_and_pointing/cron_submit_slot.pl

    # manual back-fill for a specific 3-hour slot:
    ./cron_submit_slot.pl -y=2026 -mo=3 -d=28 -h=0
```

Accepted options: `-year`, `-month`, `-day`, `-hour` (all integers), `-dry-run`.

### pipeline_slot_nrt.csh

The pipeline script launched by `cron_submit_slot.pl`.
Takes four positional arguments — `year month day hour` — and orchestrates the three-stage NRT pipeline:

1. `run_limbfit_ymdh.pl` — runs `limbfit_aia` and writes `.limb` files.
2. `lf2mpr_nrt.pdl` — reduces `.limb` files to a `masterpoint_*.txt`.
3. `update3h_mpt.pl` — merges that file into `aia.master_pointing3h` in DRMS.

Can also be run directly to process a specific slot without going through the cron wrapper:

```console
    ./pipeline_slot_nrt.csh 2026 3 28 0
```

### run_limbfit_ymdh.pl

Runs the `limbfit_aia` DRMS module once per wavelength for the requested 3-hour interval.
For each wavelength `w` in `$cfg->{wl}` it constructs a DRMS query of the form:

```console
aia.lev1_nrt2[YYYY.MM.DD_HH/3h][?WAVELNTH=w?]<drms_filter>
```

and invokes `limbfit_aia` with a `sum=` value chosen by wavelength (5 for λ < 1500 Å, 3 for 1500 Å ≤ λ < 4000 Å, 1 for 4500 Å).
Output `.limb` files are written to:

```console
$fits_root/YYYY/MM/DD/YYYYMMDD_HH_WWWW.limb
```

Options: `-filter`, `-series`, `-outroot`, `-year`, `-month`, `-day`, `-hour`, `-dur`, `-dry-run`.

### lf2mpr_nrt.pdl

Reads all `.limb` files for a given 3-hour interval and wavelength set and applies a two-pass sigma-clipping algorithm to produce robust centre-of-disk estimates:

- **Pass 1** — rejects individual limb fits whose 2D distance from the sample mean exceeds 2 σ.
- **Pass 2** — rejects any further outliers that are more than 3 σ from the mean of the pass-1 survivors (σ measured on the survivors).

The sigma multipliers and cutoff baselines are configurable through `config.pl` (`sigma_clip_pass1_sigma`, `sigma_clip_pass2_sigma`, `sigma_clip_pass1_baseline`, `sigma_clip_pass2_baseline`).

For non-4500 Å channels, the reducer also checks for obvious split-cluster files by looking for one dominant temporal jump that separates two large, well-separated segments. When `split_cluster_mode` is `fail`, `lf2mpr_nrt.pdl` aborts with segment diagnostics instead of averaging across both clouds.

The 4500 Å channel is handled specially: sigma clipping is skipped entirely and rows matching `nan_sentinel` (1234567) are excluded instead.

Output is appended to a single file per interval:

```console
$outdir/masterpoint_YYYYMMDD_HHMM_3hcadence.txt
```

Each entry has the form `KWD A_WWW_X0  <value>` / `KWD A_WWW_Y0  <value>`.
If either average is NaN and the `-email` flag is passed, an alert is sent to `$cfg->{mail_to}`. The production `pipeline_slot_nrt.csh` is the only caller that enables this.

Options: `-inpdir`, `-outdir`, `-stgdir` (stage directory), `-stage` (copy to stage), `-year`, `-month`, `-day`, `-hour`, `-dur`.

#### Known edge cases

- **Zero-scatter (non-4500 Å)** — If a `.limb` file for 94–1700 Å contains 3+ perfectly identical `x0`/`y0` samples, the sigma-clipping standard deviation is zero. The rejection threshold is therefore zero, and the strict `<` comparison keeps all points (distance 0 is not less than threshold 0), so the mean is the common value — not NaN. 4500 Å is unaffected because it bypasses sigma clipping entirely.

- **Old two-row 4500 Å sentinel leak (fixed)** — In previous versions the `nan_sentinel` filter for 4500 Å lived inside the sigma-clipping block, which is only entered when `dim(0) >= 3`. A 4500 Å file with only 1–2 rows would bypass the filter and average the sentinel value (`1234567`) into the result. The current code filters sentinels before the `< 3` shortcut, fixing this.

- **Column-reading caveat for 4500 Å** — The reducer loads only columns 0 and 1 (`x0`, `y0`) from `.limb` files. The `nan_sentinel` check therefore assumes `limbfit_aia` writes the sentinel into both `x0` and `y0` for bad 4500 Å rows. If the binary ever flags bad rows only in `radius` or `ref_radius`, the reducer will not catch them.

### update3h_mpt.pl

Merges `masterpoint_*.txt` files from the stage directory into the DRMS series `aia.master_pointing3h`.
For each file it:

1. Queries `sdo.master_pointing` to find the matching spacecraft-attitude record for the interval's `T_START`.
2. Checks whether a record for that `T_START` already exists in `aia.master_pointing3h`; if it does and the existing record is newer than the file on disk, the file is skipped (age guard).
3. Merges all `KWD` entries from the file with the spacecraft-attitude keywords and writes or updates the DRMS record.

**Timestamp mapping:** The masterpoint filename encodes the **centre** of the slot (e.g. `masterpoint_20260501_0130_3hcadence.txt` for the 00:00–03:00 window). `update3h_mpt.pl` maps this to slot **boundaries** when writing to DRMS, so `T_START` is `00:00:00Z` and `T_STOP` is `03:00:00Z`.

Useful options:

| Option | Effect |
| ------ | ------ |
| `-delete` | Delete each `masterpoint_*.txt` after it is committed |
| `-dry-run` | Print the `set_info` commands that would run |
| `-series=S` | Override target DRMS series (default `aia.master_pointing3h`) |
| `-srcdir=D` | Override source directory |

**Deleting bad records:** If incorrect records were committed (e.g. wrong timestamps or truncated slots), remove them with `delete_records` before re-ingesting:

```console
/home/phil/jsoc/bin/linux_x86_64/delete_records 'ds=aia.master_pointing3h[2026.05.02/1d]'
```

The argument is any valid DRMS record-set query. Always verify the selection with `show_info -q` first.

### update_nans.pl

Repairs NaN / missing entries in `aia.master_pointing3h` after a gap-fill `.limb` file has been produced.
This is the standard workflow for back-filling intervals identified by `lf_inv.pl` or from an `aia.master_pointing3h_miss.*` file.

Reads whitespace-separated records from stdin:

```console
YYYY-MM-DDTHH:MM:SSZ  wavelength  x_centre  y_centre
```

For each record it:

1. Locates the corresponding `.limb` file under `fits_root`.
2. Patches it in-place with the sed script at `lf_sed` (`sed -i -f $lf_sed {file}`). The sed script replaces sentinel / NaN values; `x_centre` and `y_centre` from stdin are available for reference but the patching logic lives in the sed script itself.
3. Re-reduces the patched `.limb` through `lf2mpr_nrt.pdl` into `update_dir`.
4. Commits the corrected result via `update3h_mpt.pl`.

Typical workflow (as documented in `NotesLimbFit.txt`):

```console
    grep ^2024 /path/to/missing/aia.master_pointing3h_miss.171 \
      | /homef/nabil/Git/aia_limbfit_and_pointing/update_nans.pl
```

Use `-dry-run` to print the `sed`, `lf2mpr_nrt.pdl`, and `update3h_mpt.pl` commands without modifying files or DRMS.

**Warning:** This script modifies `.limb` files **in-place** (`sed -i`). Make sure you are patching the correct file set before piping data into it.

**Note:** `lf_sed` must point to a sed script that replaces sentinel / NaN values in `.limb` files.
This script is machine-local and is not stored in the repository; its path is set in `config.pl`.

### check_pointing_gaps.pl

DRMS gap inventory for the pointing table.
Queries `aia.master_pointing3h` (or another series) for `T_START`, `T_STOP`, and all per-wavelength `A_www_X0`/`A_www_Y0` keywords, then reports three kinds of problems:

- **Temporal gaps** — missing 3-hour slots where consecutive records don't abut.
- **Slot issues** — off-grid, wrong-duration, zero-duration, or overlapping records.
- **Wavelength gaps** — existing records where one or more wavelengths have bad values (NaN, MISSING, or the nan sentinel).

When no start date is specified the script defaults to `2010-11-01`. When no end date is specified it defaults to **7 days ago** (the most recent complete week), so incomplete data at the tail end is ignored.

```console
    ./check_pointing_gaps.pl                                       # full pipeline: report + execute + patch.txt
    ./check_pointing_gaps.pl -year=2024 -month=3 -day=1           # single day (end defaults to same day)
    ./check_pointing_gaps.pl -year=2024 -month=3 -day=1 \
      -end_year=2024 -end_month=6 -end_day=1                      # explicit range
    ./check_pointing_gaps.pl -report-only                         # report without backfilling
    ./check_pointing_gaps.pl -plots                                # only regenerate plots
```

Options:

| Option | Effect |
| ------ | ------ |
| `-year`, `-month`, `-day` | Start date (defaults to `2010-11-01`); if all three are given and no end date is set, end defaults to the same day |
| `-end_year`, `-end_month`, `-end_day` | End date (defaults to 7 days ago) |
| `-series=S` | Override target DRMS pointing series |
| `-image_series=S` | Override image source series (default `aia.lev1_nrt2`; auto-falls back to `aia.lev1` for slots before 2022-06-08) |
| `-plots` | Only regenerate plots for existing `.limb` files |
| `-report-only` | Print gap/issue report without running any backfill commands |
| `-dry-run` | Print backfill commands without executing them |

**Resume-safe behavior:** The script checks whether `.limb` files already exist before re-running a slot. If they exist and are non-empty the slot is skipped; if they are empty (0 bytes) they are removed and the slot is reprocessed. This makes it safe to re-run the same command after a partial failure.

**Patch file:** Wavelength gaps are automatically written to `$outdir/patch.txt` in `update_nans.pl` format. Feed the file to `update_nans.pl` to patch NaN entries.

### lf_inv.pl

Gap inventory tool.
Walks every expected `.limb` file — all wavelengths at every 3-hour slot — from a start date to approximately 24 hours before the current time (the 24-hour buffer avoids flagging slots that are still in progress) and prints any files that are absent.
Use the output to identify intervals that need a back-fill run.

```console
    ./lf_inv.pl                           # scan from 2017-01-01
    ./lf_inv.pl -year=2024 -month=3       # scan from 2024-03-01
    ./lf_inv.pl -fits_root=/other/path    # override fits directory
```

Each missing file is reported on its own line:

```console
/path/to/fits_root/YYYY/MM/DD/YYYYMMDD_HH_WWWW.limb missing
```

Options: `-fits_root`, `-year`, `-month`, `-day`.

### run_limbfit_test.pl

Single-wavelength debug variant of `run_limbfit_ymdh.pl`.
Runs `limbfit_aia` for one wavelength (default 304 Å) against `aia.lev1` (science-quality) instead of `aia.lev1_nrt2`, without triggering a full pipeline run.
The same sum-by-wavelength logic applies (5 for w < 1500, 3 for w < 4000, 1 for 4500).

Useful for isolating a wavelength-specific problem or verifying a fix on a past interval before committing to a full back-fill.

```console
    ./run_limbfit_test.pl -y=2024 -mo=3 -da=28 -h=0 -wavel=171
```

Options: all of the same options as `run_limbfit_ymdh.pl` plus `-wavel=WL` to specify the single wavelength.
By default it writes into `test_fits_root` from `config.pl` so debug runs do not land in the production `fits_root` tree.
It also writes a diagnostic PNG next to the generated `.limb` file unless `-no-plots` is passed.
Use `-dry-run` to print the `limbfit_aia` command without running it.

### plot_limb.py

Diagnostic plotter for raw `.limb` files.
It accepts one `.limb` file, invokes the real PDL reducer (`lf2mpr_nrt.pdl`) in a temp directory, and writes one PNG showing the raw data plus the reducer's final centre (gold star) or the reducer error message.

Because it shells out to `lf2mpr_nrt.pdl`, this script also needs a working Perl/PDL install (including `PDL::Stats`) and the repo's `config.pl` must be readable from the invocation directory. Use `--no-reducer` to skip the Perl call and plot raw data only.

```console
    ./plot_limb.py data/20260326_18_0304.limb -o /tmp/0304_diagnostic.png
    ./plot_limb.py /path/to/failed_slot.limb
```

Arguments:

| Argument | Meaning |
| -------- | ------- |
| `limb_file` | One `.limb` file to plot |
| `-o`, `--output` | Optional PNG file to create |
| `--no-reducer` | Skip invoking the Perl reducer; plot raw data only |
| `--nan-sentinel` | Sentinel value to treat as invalid (default `1234567`) |
| `--perl` | Path to the Perl interpreter for the PDL reducer (default: perlbrew Perl) |

This script requires `pandas`, `matplotlib`, and `numpy`.
