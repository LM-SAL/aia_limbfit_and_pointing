#!/usr/bin/env python3
"""
Plot diagnostics for a single raw .limb file.

By default this script invokes the real PDL reducer (lf2mpr_nrt.pdl).
This ensures that the summary statistics match production,
but it also means the script has a Perl dependency.
"""

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "matplotlib"))

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D


DEFAULT_SENTINEL = 1234567.0
REDUCER_NAME = "lf2mpr_nrt.pdl"
DEFAULT_PERL = "/home/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl"


@dataclass
class LimbData:
    path: Path
    frame: pd.DataFrame
    invalid_mask: np.ndarray
    reducer_center: tuple[float, float] | None = None
    reducer_error: str | None = None
    reducer_accepted_mask: np.ndarray | None = None
    reducer_rejected_mask: np.ndarray | None = None
    context: pd.DataFrame | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Plot one raw .limb file and write one diagnostic PNG. "
            "The real PDL reducer is invoked by default so the summary "
            "statistics match production."
        )
    )
    parser.add_argument("limb_file", help="Path to the .limb file to plot")
    parser.add_argument(
        "-o",
        "--output",
        help="PNG file to create. Defaults to <limb_file stem>_diagnostic.png.",
    )
    parser.add_argument(
        "--no-reducer",
        action="store_true",
        help="Skip invoking the Perl reducer; plot raw data only.",
    )
    parser.add_argument(
        "--nan-sentinel",
        type=float,
        default=DEFAULT_SENTINEL,
        help=(
            "Sentinel value to treat as invalid. Default: %(default)s "
            "(the value used by the reducer for bad limbfit outputs)."
        ),
    )
    parser.add_argument(
        "--perl",
        default=DEFAULT_PERL,
        help="Path to the Perl interpreter used to run the PDL reducer. Default: %(default)s",
    )
    parser.add_argument(
        "--context",
        help="Path to a context file with historical DRMS points (T_START, X0, Y0). "
        "Auto-discovered if omitted and the .limb file lives under a 'limb/' directory.",
    )
    return parser.parse_args()


def resolve_input_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if not path.is_file():
        raise FileNotFoundError(f"No file found at '{raw_path}'")
    if path.suffix != ".limb":
        raise ValueError(f"Expected a .limb file, got '{raw_path}'")
    return path.resolve()


def infer_output_path(path: Path, output: str | None) -> Path:
    if output:
        return Path(output)
    return Path(f"{path.stem}_diagnostic.png")


def find_context_file(limb_path: Path) -> Path | None:
    """Auto-discover a context file parallel to the limb file."""
    parts = list(limb_path.parts)
    if "limb" not in parts:
        return None
    idx = parts.index("limb")
    ctx_parts = parts[:idx] + ["context"] + parts[idx + 1 : -1]
    ctx_dir = Path(*ctx_parts)
    candidate = ctx_dir / f"{limb_path.stem}_context.txt"
    return candidate if candidate.is_file() else None


def load_context_file(path: Path) -> pd.DataFrame | None:
    """Read a context file written by check_pointing_gaps.pl."""
    try:
        df = pd.read_csv(
            path,
            sep=r"\s+",
            header=None,
            names=["t_start", "x_center", "y_center"],
        )
    except Exception:
        return None
    if df.empty:
        return None
    for col in ("x_center", "y_center"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=["x_center", "y_center"])
    return df if len(df) else None


def compute_reducer_masks(
    frame: pd.DataFrame,
    invalid_mask: np.ndarray,
    wavelength: int,
    pass1_sigma: float = 2.0,
    pass1_baseline: str = "zero",
    pass2_sigma: float = 3.0,
    pass2_baseline: str = "mean",
) -> tuple[np.ndarray, np.ndarray]:
    """
    Replicate the two-pass sigma-clipping logic from lf2mpr_nrt.pdl.

    Returns (accepted_mask, rejected_mask) aligned to the full frame.
    Both are False for invalid rows.
    """
    valid_idx = np.where(~invalid_mask)[0]
    if len(valid_idx) == 0:
        return (
            np.zeros(len(frame), dtype=bool),
            np.zeros(len(frame), dtype=bool),
        )

    x = frame.loc[~invalid_mask, "x_center"].to_numpy()
    y = frame.loc[~invalid_mask, "y_center"].to_numpy()

    if len(x) < 3:
        accepted = np.zeros(len(frame), dtype=bool)
        accepted[valid_idx] = True
        return accepted, np.zeros(len(frame), dtype=bool)

    # 4500 Å skips sigma clipping and only drops NaN sentinels
    if wavelength == 4500:
        accepted = np.zeros(len(frame), dtype=bool)
        accepted[valid_idx] = True
        return accepted, np.zeros(len(frame), dtype=bool)

    # Pass 1
    x_avg = np.mean(x)
    y_avg = np.mean(y)
    cd = np.sqrt((x - x_avg) ** 2 + (y - y_avg) ** 2)
    baseline1 = np.mean(cd) if pass1_baseline == "mean" else 0.0
    mask1 = cd < pass1_sigma * np.std(cd, ddof=1) + baseline1

    if not mask1.any():
        return (
            np.zeros(len(frame), dtype=bool),
            np.zeros(len(frame), dtype=bool),
        )

    # Pass 2 (on points that survived pass 1)
    xp = x[mask1]
    yp = y[mask1]
    xdp = xp - np.mean(xp)
    ydp = yp - np.mean(yp)
    cp = np.sqrt(xdp**2 + ydp**2)
    baseline2 = np.mean(cp) if pass2_baseline == "mean" else 0.0
    mask2 = cp < pass2_sigma * np.std(cp, ddof=1) + baseline2

    accepted = np.zeros(len(frame), dtype=bool)
    rejected = np.zeros(len(frame), dtype=bool)

    pass1_idx = valid_idx[mask1]
    accepted[pass1_idx[mask2]] = True
    rejected[valid_idx] = True
    rejected[pass1_idx[mask2]] = False

    return accepted, rejected


def load_limb_file(path: Path, nan_sentinel: float) -> LimbData:
    frame = pd.read_csv(
        path,
        sep=r"\s+",
        header=None,
        names=[
            "x_center",
            "y_center",
            "radius",
            "epoch",
            "timestamp",
            "reference_radius",
        ],
    )
    if frame.empty:
        raise ValueError(f"'{path}' is empty")

    for column in ["x_center", "y_center", "radius", "epoch", "reference_radius"]:
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    frame["timestamp"] = pd.to_datetime(frame["timestamp"], utc=True, errors="coerce")
    frame["sample_index"] = np.arange(len(frame))

    invalid_mask = (
        ~np.isfinite(frame["x_center"])
        | ~np.isfinite(frame["y_center"])
        | ~np.isfinite(frame["radius"])
        | frame["x_center"].eq(nan_sentinel)
        | frame["y_center"].eq(nan_sentinel)
        | frame["radius"].eq(nan_sentinel)
    ).to_numpy()

    return LimbData(
        path=path,
        frame=frame,
        invalid_mask=invalid_mask,
    )


def attach_reducer_masks(data: LimbData, wavelength: int) -> None:
    if data.reducer_center is None or data.reducer_error is not None:
        return
    accepted, rejected = compute_reducer_masks(data.frame, data.invalid_mask, wavelength)
    data.reducer_accepted_mask = accepted
    data.reducer_rejected_mask = rejected


def parse_limb_filename(path: Path) -> dict:
    """Extract yr, mo, da, hr, wl from a filename like 20251224_09_0171.limb."""
    stem = path.stem
    m = re.fullmatch(r"(\d{4})(\d{2})(\d{2})_(\d{2})_(\d+)", stem)
    if not m:
        raise ValueError(
            f"Filename '{path.name}' does not match expected pattern YYYYMMDD_HH_WWWW.limb"
        )
    return {
        "yr": m.group(1),
        "mo": m.group(2),
        "da": m.group(3),
        "hr": m.group(4),
        "wl": int(m.group(5)),
    }


def run_reducer(limb_path: Path, perl_bin: str) -> tuple[tuple[float, float] | None, str | None]:
    """Invoke lf2mpr_nrt.pdl on a single .limb file and return (x0, y0) or an error."""
    repo_root = Path(__file__).parent.resolve()
    reducer = repo_root / REDUCER_NAME
    if not reducer.is_file():
        return None, f"Reducer not found: {reducer}"

    info = parse_limb_filename(limb_path)
    dur = 3

    tmpdir = Path(tempfile.mkdtemp(prefix="limbfit_plot_"))
    try:
        inpdir = tmpdir / "in"
        outdir = tmpdir / "out"
        outdir.mkdir(parents=True)
        nested = inpdir / info["yr"] / info["mo"] / info["da"]
        nested.mkdir(parents=True)

        target = nested / f"{info['yr']}{info['mo']}{info['da']}_{info['hr']}_{info['wl']:04d}.limb"
        target.symlink_to(limb_path)

        cmd = [
            perl_bin,
            str(reducer),
            f"-year={info['yr']}",
            f"-month={info['mo']}",
            f"-day={info['da']}",
            f"-hour={info['hr']}",
            f"-inpdir={inpdir}",
            f"-outdir={outdir}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            err = (
                result.stderr.strip().splitlines()[0]
                if result.stderr.strip()
                else "Reducer exited with error"
            )
            return None, err

        h = int(info["hr"]) + dur * 0.5
        m = int(60 * (h - int(h)))
        outbase = f"masterpoint_{info['yr']}{info['mo']}{info['da']}_{int(h):02d}{m:02d}_{dur}hcadence.txt"
        outpath = outdir / outbase
        if not outpath.is_file():
            return None, f"Reducer did not create expected output: {outbase}"

        x0 = y0 = None
        key_x = f"A_{info['wl']:03d}_X0"
        key_y = f"A_{info['wl']:03d}_Y0"
        with open(outpath) as fh:
            for line in fh:
                if line.startswith("KWD"):
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        if parts[1] == key_x:
                            x0 = float(parts[2])
                        elif parts[1] == key_y:
                            y0 = float(parts[2])
        if x0 is None or y0 is None:
            return None, "Output file missing X0/Y0 keywords for this wavelength"
        return (x0, y0), None
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def summarize(data: LimbData) -> None:
    print("Raw .limb summary:")
    frame = data.frame
    valid_frame = frame.loc[~data.invalid_mask]
    x_mean = valid_frame["x_center"].mean()
    y_mean = valid_frame["y_center"].mean()
    r_mean = valid_frame["radius"].mean()
    print(
        "  "
        f"{data.path.name}: rows={len(frame)}, valid={len(valid_frame)}, "
        f"invalid={int(data.invalid_mask.sum())}, "
        f"x_mean={x_mean:.3f}, y_mean={y_mean:.3f}, r_mean={r_mean:.3f}"
    )
    if data.reducer_error:
        print(f"  Reducer: FAILED — {data.reducer_error}")
    elif data.reducer_center:
        x0, y0 = data.reducer_center
        print(f"  Reducer: x0={x0:.3f}, y0={y0:.3f}")


def plot_data(data: LimbData, output_path: Path) -> None:
    use_time_axis = data.frame["timestamp"].notna().all()
    fig, axes = plt.subplots(2, 2, figsize=(16, 11))
    ax_x, ax_y = axes[0]
    ax_r, ax_xy = axes[1]
    frame = data.frame
    x_axis = frame["timestamp"] if use_time_axis else frame["sample_index"]
    valid = frame.loc[~data.invalid_mask]
    invalid = frame.loc[data.invalid_mask]
    valid_x_axis = x_axis[~data.invalid_mask]
    invalid_x_axis = x_axis[data.invalid_mask]
    accepted_mask = data.reducer_accepted_mask
    rejected_mask = data.reducer_rejected_mask
    has_rejection_info = accepted_mask is not None and rejected_mask is not None

    for axis, column in [
        (ax_x, "x_center"),
        (ax_y, "y_center"),
        (ax_r, "radius"),
    ]:
        if has_rejection_info and axis in (ax_x, ax_y):
            # Show full trend as a faint blue line, overlay accepted/rejected markers
            axis.plot(
                valid_x_axis,
                valid[column],
                color="tab:blue",
                linewidth=1.1,
                alpha=0.4,
            )
            accepted_pts = frame.loc[accepted_mask]
            rejected_pts = frame.loc[rejected_mask]
            if not accepted_pts.empty:
                axis.scatter(
                    x_axis[accepted_mask],
                    accepted_pts[column],
                    color="tab:green",
                    s=30,
                    alpha=0.8,
                    zorder=5,
                )
            if not rejected_pts.empty:
                axis.scatter(
                    x_axis[rejected_mask],
                    rejected_pts[column],
                    color="tab:red",
                    s=24,
                    alpha=0.7,
                    zorder=5,
                )
        else:
            axis.plot(
                valid_x_axis,
                valid[column],
                color="tab:blue",
                marker="o",
                linewidth=1.1,
                markersize=3,
                label="valid samples",
            )
        if not invalid.empty:
            axis.scatter(
                invalid_x_axis,
                invalid[column],
                color="crimson",
                marker="x",
                s=50,
                label="invalid / sentinel",
            )

    if valid["reference_radius"].notna().any():
        ax_r.axhline(
            valid["reference_radius"].median(),
            color="0.45",
            linestyle="--",
            linewidth=1.0,
            alpha=0.7,
            label="reference radius",
        )

    if has_rejection_info:
        accepted = frame.loc[accepted_mask]
        rejected = frame.loc[rejected_mask]
        if not accepted.empty:
            ax_xy.scatter(
                accepted["x_center"],
                accepted["y_center"],
                color="tab:green",
                s=30,
                alpha=0.8,
                label="accepted by reducer",
            )
        if not rejected.empty:
            ax_xy.scatter(
                rejected["x_center"],
                rejected["y_center"],
                color="tab:red",
                s=24,
                alpha=0.7,
                label="rejected by reducer",
            )
    else:
        ax_xy.scatter(
            valid["x_center"],
            valid["y_center"],
            color="tab:blue",
            s=24,
            alpha=0.7,
            label="valid samples",
        )
    if not invalid.empty:
        ax_xy.scatter(
            invalid["x_center"],
            invalid["y_center"],
            color="crimson",
            marker="x",
            s=50,
            linewidths=1.2,
            label="invalid / sentinel",
        )

    # Overlay historical context points if available
    if data.context is not None:
        ctx = data.context
        ax_xy.scatter(
            ctx["x_center"],
            ctx["y_center"],
            color="0.65",
            s=12,
            alpha=0.5,
            label="DRMS context (±3 d)",
        )

    # Overlay reducer output if available
    if data.reducer_center:
        x0, y0 = data.reducer_center
        ax_x.axhline(x0, color="goldenrod", linestyle="--", linewidth=1.5, alpha=0.8)
        ax_y.axhline(y0, color="goldenrod", linestyle="--", linewidth=1.5, alpha=0.8)
        ax_xy.scatter(
            [x0],
            [y0],
            color="goldenrod",
            marker="*",
            s=220,
            edgecolors="black",
            linewidths=0.8,
            zorder=5,
            label="reducer center",
        )

    ax_x.set_title("X Center")
    ax_x.set_ylabel("Pixels")
    ax_y.set_title("Y Center")
    ax_y.set_ylabel("Pixels")
    ax_r.set_title("Radius")
    ax_r.set_ylabel("Pixels")
    ax_xy.set_title("Center Scatter")
    ax_xy.set_xlabel("X Center (pixels)")
    ax_xy.set_ylabel("Y Center (pixels)")
    ax_xy.set_aspect("equal")

    for axis in [ax_x, ax_y, ax_r]:
        axis.set_xlabel("Timestamp" if use_time_axis else "Sample index")
    for axis in axes.flat:
        axis.grid(True, alpha=0.3)

    if use_time_axis:
        locator = mdates.AutoDateLocator()
        formatter = mdates.ConciseDateFormatter(locator)
        for axis in [ax_x, ax_y, ax_r]:
            axis.xaxis.set_major_locator(locator)
            axis.xaxis.set_major_formatter(formatter)

    legend_handles = []
    if has_rejection_info:
        if not accepted.empty:
            legend_handles.append(
                Line2D(
                    [0],
                    [0],
                    color="tab:green",
                    marker="o",
                    linestyle="None",
                    markersize=5,
                    label="accepted by reducer",
                )
            )
        if not rejected.empty:
            legend_handles.append(
                Line2D(
                    [0],
                    [0],
                    color="tab:red",
                    marker="o",
                    linestyle="None",
                    markersize=5,
                    label="rejected by reducer",
                )
            )
    else:
        legend_handles.append(
            Line2D(
                [0],
                [0],
                color="tab:blue",
                marker="o",
                linewidth=1.1,
                markersize=5,
                label="valid samples",
            )
        )
    if data.context is not None:
        legend_handles.append(
            Line2D(
                [0],
                [0],
                color="0.65",
                marker="o",
                linestyle="None",
                markersize=4,
                label="DRMS context (±3 d)",
            )
        )
    if not invalid.empty:
        legend_handles.append(
            Line2D(
                [0],
                [0],
                color="crimson",
                marker="x",
                linestyle="None",
                markersize=7,
                markeredgewidth=1.2,
                label="invalid / sentinel",
            )
        )
    if data.reducer_center:
        legend_handles.append(
            Line2D(
                [0],
                [0],
                color="goldenrod",
                marker="*",
                linestyle="--",
                markersize=10,
                markeredgewidth=0.8,
                markeredgecolor="black",
                linewidth=1.5,
                label="reducer center",
            )
        )
    if valid["reference_radius"].notna().any():
        legend_handles.append(
            Line2D(
                [0],
                [0],
                color="0.45",
                linestyle="--",
                linewidth=1.0,
                label="reference radius",
            )
        )

    fig.suptitle(
        f"Raw Limb-Fit Diagnostics: {data.path.name}",
        fontsize=16,
        fontweight="bold",
        y=0.992,
    )
    if data.reducer_error:
        fig.text(
            0.5,
            0.965,
            f"Reducer failed: {data.reducer_error}",
            ha="center",
            fontsize=9,
            color="darkred",
            wrap=True,
        )
    if legend_handles:
        fig.legend(
            legend_handles,
            [handle.get_label() for handle in legend_handles],
            loc="upper center",
            bbox_to_anchor=(0.5, 0.962),
            ncol=min(len(legend_handles), 4),
            frameon=False,
        )
    fig.tight_layout(rect=(0, 0, 1, 0.90))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    args = parse_args()

    try:
        limb_file = resolve_input_path(args.limb_file)
        data = load_limb_file(limb_file, args.nan_sentinel)
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}")
        return 1

    if not args.no_reducer:
        center, err = run_reducer(limb_file, args.perl)
        data.reducer_center = center
        data.reducer_error = err

    info = parse_limb_filename(limb_file)
    attach_reducer_masks(data, info["wl"])

    ctx_path = Path(args.context) if args.context else find_context_file(limb_file)
    if ctx_path is not None:
        data.context = load_context_file(ctx_path)

    output_path = infer_output_path(limb_file, args.output)
    summarize(data)
    plot_data(data, output_path)
    print(f"Plot saved to: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
