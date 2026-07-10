#!/usr/bin/env python3
"""Plot raw ``.limb`` data and annotate the production reducer result."""

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "matplotlib"))

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


DEFAULT_SENTINEL = 1234567.0
DEFAULT_PERL = "/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plot one raw .limb file and report the production reducer result."
    )
    parser.add_argument("limb_file")
    parser.add_argument("-o", "--output", help="PNG path; defaults to <stem>_diagnostic.png")
    parser.add_argument(
        "--no-reducer", action="store_true", help="Plot without running the reducer"
    )
    parser.add_argument("--nan-sentinel", type=float, default=DEFAULT_SENTINEL)
    parser.add_argument("--perl", default=DEFAULT_PERL, help="Perl used to run lf2mpr_nrt.pdl")
    return parser.parse_args()


def resolve_input_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if not path.is_file():
        raise FileNotFoundError(f"No file found at '{raw_path}'")
    if path.suffix != ".limb":
        raise ValueError(f"Expected a .limb file, got '{raw_path}'")
    return path.resolve()


def load_limb(path: Path, sentinel: float) -> tuple[np.ndarray, np.ndarray]:
    values = np.loadtxt(path, usecols=(0, 1, 2, 5), ndmin=2)
    if values.shape[0] == 0:
        raise ValueError(f"'{path}' is empty")
    valid = np.isfinite(values[:, :3]).all(axis=1)
    valid &= ~(values[:, :3] == sentinel).any(axis=1)
    return values, valid


def parse_limb_filename(path: Path) -> tuple[str, str, str, str, int]:
    match = re.fullmatch(r"(\d{4})(\d{2})(\d{2})_(\d{2})_(\d+)", path.stem)
    if not match:
        raise ValueError(f"Filename '{path.name}' must match YYYYMMDD_HH_WWWW.limb")
    year, month, day, hour, wavelength = match.groups()
    return year, month, day, hour, int(wavelength)


def reducer_error(result: subprocess.CompletedProcess[str], fallback: str) -> str:
    return " ".join(result.stderr.split()) or fallback


def run_reducer(path: Path, perl: str) -> tuple[tuple[float, float] | None, str | None]:
    try:
        year, month, day, hour, wavelength = parse_limb_filename(path)
    except ValueError as error:
        return None, str(error)

    reducer = Path(__file__).with_name("lf2mpr_nrt.pdl")
    if not reducer.is_file():
        return None, f"Reducer not found: {reducer}"

    with tempfile.TemporaryDirectory(prefix="limbfit_plot_") as temporary:
        root = Path(temporary)
        input_dir = root / "in"
        output_dir = root / "out"
        nested = input_dir / year / month / day
        nested.mkdir(parents=True)
        output_dir.mkdir()
        (nested / path.name).symlink_to(path)

        result = subprocess.run(
            [
                perl,
                str(reducer),
                f"-year={year}",
                f"-month={month}",
                f"-day={day}",
                f"-hour={hour}",
                f"-inpdir={input_dir}",
                f"-outdir={output_dir}",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode:
            return None, reducer_error(result, f"Reducer exited with status {result.returncode}")

        center_hour = int(hour) + 1.5
        output = output_dir / (
            f"masterpoint_{year}{month}{day}_{int(center_hour):02d}"
            f"{int(60 * (center_hour % 1)):02d}_3hcadence.txt"
        )
        if not output.is_file():
            return None, f"Reducer did not create {output.name}"

        centers: dict[str, float] = {}
        keys = {f"A_{wavelength:03d}_X0": "x", f"A_{wavelength:03d}_Y0": "y"}
        for line in output.read_text().splitlines():
            fields = line.split()
            if len(fields) >= 3 and fields[0] == "KWD" and fields[1] in keys:
                centers[keys[fields[1]]] = float(fields[2])

        if centers.keys() != {"x", "y"}:
            return None, "Reducer output is missing X0/Y0"
        center = (centers["x"], centers["y"])
        if not np.isfinite(center).all():
            return None, reducer_error(result, "Reducer returned non-finite X0/Y0")
        return center, None


def summarize(
    path: Path,
    values: np.ndarray,
    valid: np.ndarray,
    center: tuple[float, float] | None,
    error: str | None,
) -> None:
    print(
        f"Raw .limb summary: {path.name}: rows={len(values)}, "
        f"valid={valid.sum()}, invalid={(~valid).sum()}"
    )
    if valid.any():
        x_mean, y_mean, radius_mean = values[valid, :3].mean(axis=0)
        print(f"  raw means: x={x_mean:.3f}, y={y_mean:.3f}, radius={radius_mean:.3f}")
    if error:
        print(f"  Reducer: FAILED — {error}")
    elif center:
        print(f"  Reducer: x0={center[0]:.3f}, y0={center[1]:.3f}")


def plot_limb(
    path: Path,
    values: np.ndarray,
    valid: np.ndarray,
    center: tuple[float, float] | None,
    error: str | None,
    sentinel: float,
    output: Path,
) -> None:
    x_center, y_center, radius, reference = values.T
    sample = np.arange(len(values))
    figure, axes = plt.subplots(2, 2, figsize=(14, 10))
    ax_x, ax_y = axes[0]
    ax_radius, ax_xy = axes[1]

    for axis, data, title in (
        (ax_x, x_center, "X Center"),
        (ax_y, y_center, "Y Center"),
        (ax_radius, radius, "Radius"),
    ):
        axis.plot(sample[valid], data[valid], "o-", markersize=3, linewidth=1)
        axis.set(title=title, xlabel="Sample index", ylabel="Pixels")

    reference_valid = valid & np.isfinite(reference) & (reference != sentinel)
    if reference_valid.any():
        ax_radius.axhline(np.median(reference[reference_valid]), color="0.5", linestyle="--")

    ax_xy.scatter(x_center[valid], y_center[valid], s=24, alpha=0.7, label="raw valid samples")
    ax_xy.set(title="Center Scatter", xlabel="X Center (pixels)", ylabel="Y Center (pixels)")
    ax_xy.set_aspect("equal")

    if center:
        ax_x.axhline(center[0], color="goldenrod", linestyle="--")
        ax_y.axhline(center[1], color="goldenrod", linestyle="--")
        ax_xy.scatter(*center, color="goldenrod", marker="*", s=220, label="reducer center")

    for axis in axes.flat:
        axis.grid(alpha=0.3)
    if ax_xy.get_legend_handles_labels()[0]:
        ax_xy.legend()

    figure.suptitle(f"Raw Limb-Fit Diagnostics: {path.name}")
    message = f"{(~valid).sum()} invalid/sentinel rows omitted"
    if error:
        message += f"\nReducer failed: {error}"
    figure.text(0.5, 0.94, message, ha="center", color="darkred" if error else "black", wrap=True)
    figure.tight_layout(rect=(0, 0, 1, 0.91))
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=150, bbox_inches="tight")
    plt.close(figure)


def main() -> int:
    args = parse_args()
    try:
        path = resolve_input_path(args.limb_file)
        values, valid = load_limb(path, args.nan_sentinel)
    except (FileNotFoundError, OSError, ValueError) as error:
        print(f"Error: {error}")
        return 1

    center, error = (None, None) if args.no_reducer else run_reducer(path, args.perl)
    output = Path(args.output) if args.output else Path(f"{path.stem}_diagnostic.png")
    summarize(path, values, valid, center, error)
    plot_limb(path, values, valid, center, error, args.nan_sentinel, output)
    print(f"Plot saved to: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
