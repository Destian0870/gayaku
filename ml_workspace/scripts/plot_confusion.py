#!/usr/bin/env python3
"""Draw the confusion matrices that `artifacts/report.md` records as markdown tables.

    python ml_workspace/scripts/plot_confusion.py
    python ml_workspace/scripts/plot_confusion.py --splits test

The counts are measured ones -- PyTorch float32 on the held-out splits, written by
`train_classifier.py` -- so this script reads them instead of re-running training. It
refuses a table whose shape, row sums, recall column or top-1 accuracy disagree with the
report's own accuracy table, so a typo in the report cannot become a figure.

Only matplotlib is needed (the rest of `ml_workspace/` stays dependency-light on purpose).
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORT = REPO_ROOT / "ml_workspace" / "bootstrap" / "artifacts" / "report.md"
DEFAULT_CLASSES = REPO_ROOT / "ml_workspace" / "bootstrap" / "artifacts" / "classes.json"

SECTION_RE = re.compile(r"^## Confusion matrix — (test|validation) \(rows true, columns predicted\)$")
ACCURACY_RE = re.compile(r"^\| (validation|test) \| ([\d.]+) \| (\d+) \|$")
ROW_RE = re.compile(r"^\*\*(.+?)\*\*$")


class PlotError(Exception):
    """The report does not say what the figure would claim."""


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise PlotError(f"{path} does not exist") from exc


def class_labels(path: Path) -> list[str]:
    import json

    doc = json.loads(read_text(path))
    labels = doc.get("labels")
    if not isinstance(labels, list) or not labels:
        raise PlotError(f"{path}: expected a non-empty 'labels' list")
    return labels


def split_table(text: str, split: str) -> list[str]:
    """The markdown table lines of one `## Confusion matrix` section."""
    lines: list[str] = []
    inside = False
    for line in text.splitlines():
        if line.startswith("## "):
            match = SECTION_RE.match(line)
            inside = match is not None and match.group(1) == split
            continue
        if inside and line.startswith("|"):
            lines.append(line)
    if not lines:
        raise PlotError(f"report.md has no confusion matrix section for {split!r}")
    return lines


def parse_matrix(lines: list[str], split: str) -> tuple[list[str], np.ndarray, np.ndarray]:
    header: list[str] | None = None
    labels: list[str] = []
    counts: list[list[int]] = []
    recalls: list[float] = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 3 or set(cells[0]) <= {"-"}:
            continue  # divider row
        if cells[0] == "true \\ pred":
            header = cells[1:-1]
            continue
        match = ROW_RE.match(cells[0])
        if match is None:
            continue
        labels.append(match.group(1))
        counts.append([int(cell) for cell in cells[1:-1]])
        recalls.append(float(cells[-1]))
    if header is None or not labels:
        raise PlotError(f"{split}: the confusion matrix table is missing its header or rows")
    if labels != header:
        raise PlotError(f"{split}: row labels and column header disagree")
    matrix = np.array(counts, dtype=np.int64)
    if matrix.shape != (len(labels), len(labels)):
        raise PlotError(f"{split}: matrix is {matrix.shape}, expected a {len(labels)}x{len(labels)} square")
    return labels, matrix, np.array(recalls, dtype=float)


def recorded_accuracy(text: str) -> dict[str, tuple[float, int]]:
    found = {}
    for line in text.splitlines():
        match = ACCURACY_RE.match(line)
        if match:
            found[match.group(1)] = (float(match.group(2)), int(match.group(3)))
    return found


def check(labels, matrix, recalls, split, accuracy, images) -> None:
    support = matrix.sum(axis=1)
    total = int(matrix.sum())
    if total != images:
        raise PlotError(f"{split}: matrix sums to {total} images, the accuracy table says {images}")
    computed = np.diag(matrix) / np.maximum(support, 1)
    if np.abs(computed - recalls).max() > 5e-4:
        worst = int(np.abs(computed - recalls).argmax())
        raise PlotError(
            f"{split}: recall column disagrees at {labels[worst]} "
            f"(table {recalls[worst]:.3f}, counts {computed[worst]:.3f})"
        )
    top1 = float(np.trace(matrix) / total)
    if abs(top1 - accuracy) > 5e-4:
        raise PlotError(f"{split}: counts give top-1 {top1:.4f}, the accuracy table says {accuracy:.4f}")


def annotate(ax, matrix: np.ndarray) -> None:
    peak = max(int(matrix.max()), 1)
    for row in range(matrix.shape[0]):
        for column in range(matrix.shape[1]):
            value = int(matrix[row, column])
            if value == 0:
                ax.text(column, row, "0", ha="center", va="center", color="#b8b8b8", fontsize=9)
                continue
            ink = "white" if value > peak * 0.55 else "#1a1a1a"
            ax.text(
                column,
                row,
                str(value),
                ha="center",
                va="center",
                color=ink,
                fontsize=9.5 if value == int(np.diag(matrix)[row]) else 9,
                fontweight="bold" if value > peak * 0.55 else "normal",
            )


def annotate(ax, matrix: np.ndarray) -> None:
    peak = max(int(matrix.max()), 1)
    for row in range(matrix.shape[0]):
        for column in range(matrix.shape[1]):
            value = int(matrix[row, column])
            if value == 0:
                ax.text(column, row, "0", ha="center", va="center", color="#c4c4c4", fontsize=9)
                continue
            ax.text(
                column,
                row,
                str(value),
                ha="center",
                va="center",
                color="white" if value > peak * 0.55 else "#1a1a1a",
                fontsize=10,
                fontweight="bold" if column == row else "normal",
            )


def draw(labels, matrix, split, accuracy, out_path: Path, dpi: int) -> None:
    support = matrix.sum(axis=1)
    recall = np.diag(matrix) / np.maximum(support, 1)
    total = int(matrix.sum())
    low = recall < accuracy  # the rows that drag the average down

    figure = plt.figure(figsize=(11.0, 8.6), facecolor="white")
    width, height = figure.get_size_inches()
    panel = 6.0

    def rect(x_in: float, y_in: float, w_in: float, h_in: float) -> list[float]:
        return [x_in / width, y_in / height, w_in / width, h_in / height]

    left, bottom = 1.35, 1.62
    ax = figure.add_axes(rect(left, bottom, panel, panel))
    ax_recall = figure.add_axes(rect(left + panel + 0.18, bottom, 1.05, panel), sharey=ax)

    ax.imshow(matrix, cmap="Blues", vmin=0)
    annotate(ax, matrix)

    ticks = np.arange(len(labels))
    ax.set_xticks(ticks)
    ax.set_yticks(ticks)
    ax.set_xticklabels(labels, rotation=45, ha="right", rotation_mode="anchor", fontsize=10)
    ax.set_yticklabels(labels, fontsize=10)
    ax.set_xlabel("Predicted", fontsize=10, labelpad=6)
    ax.set_ylabel("True", fontsize=10, labelpad=10)
    ax.set_xticks(ticks - 0.5, minor=True)
    ax.set_yticks(ticks - 0.5, minor=True)
    ax.grid(which="minor", color="white", linewidth=1.2)
    ax.tick_params(which="minor", length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)

    ax_recall.set_xlim(0, 1)
    ax_recall.set_xticks([])
    ax_recall.yaxis.set_visible(False)
    ax_recall.text(
        0.5,
        1.015,
        "recall",
        transform=ax_recall.transAxes,
        ha="center",
        va="bottom",
        fontsize=9,
        color="#666666",
    )
    for row, value in enumerate(recall):
        ax_recall.add_patch(
            Rectangle(
                (0, row - 0.5),
                1,
                1,
                color="#fbeae7" if low[row] else "#f5f6f8",
                zorder=0,
            )
        )
        ax_recall.text(
            0.5,
            row,
            f"{value:.2f}",
            ha="center",
            va="center",
            fontsize=10,
            color="#b3261e" if low[row] else "#333333",
            fontweight="bold" if low[row] else "normal",
        )
    for spine in ax_recall.spines.values():
        spine.set_visible(False)

    figure.text(
        0.45 / width,
        8.15 / height,
        f"Confusion matrix — {split} split",
        ha="left",
        va="center",
        fontsize=15,
        fontweight="bold",
        color="#111111",
    )
    figure.text(
        0.45 / width,
        7.90 / height,
        f"{total} images · top-1 {accuracy:.4f} · rows are the true label, columns the prediction\n"
        "recall is per true class; rows below the top-1 accuracy are red",
        ha="left",
        va="center",
        fontsize=10,
        color="#555555",
        linespacing=1.45,
    )
    figure.text(
        0.45 / width,
        0.30 / height,
        "Source: ml_workspace/bootstrap/artifacts/report.md — measured with PyTorch float32 on the held-out split.",
        ha="left",
        va="center",
        fontsize=8,
        color="#888888",
    )
    figure.savefig(out_path, dpi=dpi, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT, help="%(default)s")
    parser.add_argument(
        "--classes",
        type=Path,
        default=DEFAULT_CLASSES,
        help="class list whose order the columns follow (default: %(default)s)",
    )
    parser.add_argument("--out-dir", type=Path, help="default: the report's directory")
    parser.add_argument("--splits", nargs="+", default=["test", "validation"], choices=("test", "validation"))
    parser.add_argument("--dpi", type=int, default=160)
    args = parser.parse_args(argv)

    try:
        text = read_text(args.report)
        out_dir = args.out_dir or args.report.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        expected = class_labels(args.classes)
        scores = recorded_accuracy(text)
        for split in args.splits:
            if split not in scores:
                raise PlotError(f"report.md has no accuracy row for {split!r}")
            labels, matrix, recalls = parse_matrix(split_table(text, split), split)
            if labels != expected:
                raise PlotError(
                    f"{split}: matrix columns are {labels}, but {args.classes.name} lists {expected}"
                )
            accuracy, images = scores[split]
            check(labels, matrix, recalls, split, accuracy, images)
            out_path = out_dir / f"confusion_matrix_{split}.png"
            draw(labels, matrix, split, accuracy, out_path, args.dpi)
            print(f"plot_confusion: wrote {out_path} ({images} images, top-1 {accuracy:.4f})")
    except PlotError as exc:
        print(f"plot_confusion: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
