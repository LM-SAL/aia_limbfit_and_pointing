#!/usr/bin/env python3
"""Plot raw limb-fit points for operator review."""

import argparse
import os
import tempfile
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "matplotlib"))

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main() -> int:
    parser = argparse.ArgumentParser(description="Plot one raw .limb file.")
    parser.add_argument("limb_file")
    parser.add_argument("-o", "--output", help="PNG path; defaults to <stem>_diagnostic.png")
    parser.add_argument("--nan-sentinel", type=float, default=1234567.0)
    args = parser.parse_args()

    path = Path(args.limb_file)
    try:
        if path.suffix != ".limb":
            raise ValueError(f"Expected a .limb file, got '{path}'")
        values = np.loadtxt(path, usecols=(0, 1, 2, 5), ndmin=2)
        if not len(values):
            raise ValueError(f"'{path}' is empty")
    except (OSError, ValueError) as error:
        print(f"Error: {error}")
        return 1

    valid = np.isfinite(values[:, :3]).all(axis=1)
    valid &= ~(values[:, :3] == args.nan_sentinel).any(axis=1)
    output = Path(args.output) if args.output else Path(f"{path.stem}_diagnostic.png")
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

    reference_valid = valid & np.isfinite(reference) & (reference != args.nan_sentinel)
    if reference_valid.any():
        ax_radius.axhline(np.median(reference[reference_valid]), color="0.5", linestyle="--")
    ax_xy.scatter(x_center[valid], y_center[valid], s=24, alpha=0.7)
    ax_xy.set(title="Center Scatter", xlabel="X Center (pixels)", ylabel="Y Center (pixels)")
    ax_xy.set_aspect("equal")
    for axis in axes.flat:
        axis.grid(alpha=0.3)

    figure.suptitle(f"Raw Limb-Fit Diagnostics: {path.name}")
    figure.text(0.5, 0.94, f"{(~valid).sum()} invalid/sentinel rows omitted", ha="center")
    figure.tight_layout(rect=(0, 0, 1, 0.91))
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=150, bbox_inches="tight")
    plt.close(figure)
    print(f"rows={len(values)} valid={valid.sum()} invalid={(~valid).sum()} output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
