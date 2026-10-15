#!/usr/bin/env python3
"""Download and split the Kaggle product catalogue for classifier training.

    # 1. class list only -- no dataset, no Kaggle token needed; this is what the
    #    committed artifacts/classes.json comes from
    python ml_workspace/scripts/prepare_data.py --labels-only

    # 2. full prep: download, label cleanup, stratified 80/10/10 split
    python ml_workspace/scripts/prepare_data.py

    # 3. from an already extracted catalogue (Kaggle notebook input, offline copy)
    python ml_workspace/scripts/prepare_data.py --catalogue-dir /kaggle/input/fashion-product-images

Step 2 needs a Kaggle token -- ~/.kaggle/kaggle.json, or KAGGLE_USERNAME + KAGGLE_KEY in
the environment (KAGGLE_CONFIG_DIR overrides the config directory) -- and the `kaggle`
CLI (`pip install kaggle`). Step 2 fails with instructions when the token is missing;
steps 1 and 3 never touch the network.

Outputs (paths relative to ml_workspace/, override with --data-dir/--artifacts-dir):

    data/train.csv, data/val.csv, data/test.csv   id,image,label -- `image` is relative
                                                 to the catalogue root, `label` is the
                                                 articleType (the classifier's class name)
    data/split_summary.json                       per-split and per-class counts
    artifacts/classes.json                        class list (index = model class index),
                                                  read by scripts/gen_dart_labels.py

Only labels with `keep: true` in labels.json are kept, and every kept label must still
have at least MIN_IMAGES_PER_CLASS usable photographs after cleanup -- otherwise the
split cannot be stratified honestly and the script stops so that labels.json can be fixed.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import random
import shutil
import subprocess
import sys
import zipfile
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET = "paramaggarwal/fashion-product-images-dataset"
MIN_IMAGES_PER_CLASS = 8
MANIFEST_COLUMNS = ("id", "image", "label")


class PrepError(Exception):
    """A condition the maintainer has to fix before training means anything."""


def read_labels(path: Path, dataset: str) -> list[dict]:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise PrepError(f"{path} does not exist") from exc
    entries = [entry for entry in doc.get("labels", []) if entry.get("dataset") == dataset]
    if not entries:
        datasets = sorted({entry.get("dataset") for entry in doc.get("labels", [])})
        raise PrepError(
            f"{path} has no entries for dataset {dataset!r}; known datasets: {', '.join(datasets)}"
        )
    return entries


def kaggle_credentials() -> Path | None:
    """Where the kaggle CLI would find a token, or None when there is none."""
    env = Path(os.environ.get("KAGGLE_CONFIG_DIR", Path.home() / ".kaggle")) / "kaggle.json"
    if env.is_file():
        return env
    if os.environ.get("KAGGLE_USERNAME") and os.environ.get("KAGGLE_KEY"):
        return Path("$KAGGLE_USERNAME/$KAGGLE_KEY")
    return None


def download_catalogue(dataset: str, download_dir: Path) -> Path:
    download_dir.mkdir(parents=True, exist_ok=True)
    archive = download_dir / f"{dataset.split('/')[-1]}.zip"
    if archive.is_file():
        print(f"prepare_data: reusing {archive}")
        return archive
    kaggle = shutil.which("kaggle")
    if kaggle is None:
        raise PrepError(
            "the `kaggle` CLI is not installed -- run `pip install kaggle`, or pass "
            "--catalogue-dir for an already extracted dataset"
        )
    print(f"prepare_data: downloading {dataset} (several GB for the full variant)")
    subprocess.run(
        [kaggle, "datasets", "download", "-d", dataset, "-p", str(download_dir)],
        check=True,
    )
    if not archive.is_file():
        archives = sorted(download_dir.glob("*.zip"))
        if not archives:
            raise PrepError(f"kaggle wrote no .zip into {download_dir}")
        archive = archives[-1]
    return archive


def archive_style_rows(archive: Path) -> list[dict[str, str]]:
    with zipfile.ZipFile(archive) as zf:
        styles = next((n for n in zf.namelist() if n.endswith("styles.csv")), None)
        if styles is None:
            raise PrepError(f"{archive} contains no styles.csv")
        with zf.open(styles) as raw:
            text = io.TextIOWrapper(raw, encoding="utf-8", errors="replace", newline="")
            return list(csv.DictReader(text))


def extract_catalogue(archive: Path, catalogue_dir: Path, labels: set[str]) -> None:
    """Extract styles.csv plus only the photographs whose label we train on."""
    catalogue_dir.mkdir(parents=True, exist_ok=True)
    wanted = {
        (row.get("id") or "").strip()
        for row in archive_style_rows(archive)
        if (row.get("articleType") or "").strip() in labels and row.get("id")
    }
    print(f"prepare_data: extracting {len(wanted)} of the archive's photographs")
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        styles = next(n for n in names if n.endswith("styles.csv"))
        if not (catalogue_dir / "styles.csv").exists():
            with zf.open(styles) as src, (catalogue_dir / "styles.csv").open("wb") as dst:
                shutil.copyfileobj(src, dst)
        by_id = {
            Path(name).stem: name
            for name in names
            if "/images/" in name or name.startswith("images/")
        }
        for article_id in sorted(wanted):
            member = by_id.get(article_id)
            if member is None:
                continue
            target = catalogue_dir / "images" / Path(member).name
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)


def read_catalogue(catalogue_dir: Path, kept: list[str]) -> list[tuple[str, str, str]]:
    """Rows (id, image relative to catalogue_dir, label) for kept labels that have a photo."""
    styles = catalogue_dir / "styles.csv"
    if not styles.is_file():
        raise PrepError(f"{styles} is missing")
    kept_set = set(kept)
    images = catalogue_dir / "images"
    rows: list[tuple[str, str, str]] = []
    missing_files = 0
    with styles.open(encoding="utf-8", errors="replace", newline="") as fh:
        for record in csv.DictReader(fh):
            article_id = (record.get("id") or "").strip()
            label = (record.get("articleType") or "").strip()
            if not article_id or label not in kept_set:
                continue
            photo = images / f"{article_id}.jpg"
            if not photo.is_file():
                missing_files += 1
                continue
            rows.append((article_id, f"images/{photo.name}", label))
    if missing_files:
        print(f"prepare_data: {missing_files} kept rows have no photo on disk and were dropped")
    rows.sort(key=lambda row: (row[2], int(row[0])))
    seen: set[str] = set()
    deduped = [row for row in rows if not (row[0] in seen or seen.add(row[0]))]
    if len(deduped) != len(rows):
        print(f"prepare_data: dropped {len(rows) - len(deduped)} duplicate ids")
    thin = sorted(
        (label, count)
        for label, count in Counter(row[2] for row in deduped).items()
        if count < MIN_IMAGES_PER_CLASS
    )
    if thin:
        raise PrepError(
            "these kept labels have fewer than "
            f"{MIN_IMAGES_PER_CLASS} photographs: "
            + ", ".join(f"{label} ({count})" for label, count in thin)
            + " -- set keep:false for them in ml_workspace/labels.json and rerun"
        )
    return deduped


def stratified_split(
    rows: list[tuple[str, str, str]], seed: int, val_frac: float, test_frac: float
) -> dict[str, list[tuple[str, str, str]]]:
    """80/10/10 by articleType, deterministic for a given seed, mirrors the notebook."""
    rng = random.Random(seed)
    splits: dict[str, list[tuple[str, str, str]]] = {"train": [], "val": [], "test": []}
    for label in sorted({row[2] for row in rows}):
        group = [row for row in rows if row[2] == label]
        rng.shuffle(group)
        n_test = max(1, round(len(group) * test_frac))
        n_val = max(1, round(len(group) * val_frac))
        if len(group) - n_test - n_val < 1:
            raise PrepError(f"{label}: {len(group)} photographs cannot fill train/val/test")
        splits["test"] += group[:n_test]
        splits["val"] += group[n_test : n_test + n_val]
        splits["train"] += group[n_test + n_val :]
    for rows_in_split in splits.values():
        rows_in_split.sort(key=lambda row: (row[2], int(row[0])))
    return splits


def write_manifests(data_dir: Path, splits: dict[str, list[tuple[str, str, str]]]) -> dict:
    data_dir.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        with (data_dir / f"{name}.csv").open("w", encoding="utf-8", newline="") as fh:
            writer = csv.writer(fh)
            writer.writerow(MANIFEST_COLUMNS)
            writer.writerows(rows)
    per_label = {
        label: {
            name: sum(1 for row in rows if row[2] == label) for name in splits
        }
        for label in sorted({row[2] for row in splits["train"] + splits["val"] + splits["test"]})
    }
    summary = {
        "totals": {name: len(rows) for name, rows in splits.items()},
        "labels": len(per_label),
        "per_label": per_label,
    }
    (data_dir / "split_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return summary


def write_classes(
    artifacts_dir: Path,
    dataset: str,
    source: str,
    labels: list[str],
    counts: dict[str, int] | None = None,
    splits: dict[str, int] | None = None,
) -> Path:
    """Class list: labels[index] is the label the model's score `index` refers to."""
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    doc: dict = {"version": 1, "dataset": dataset, "source": source, "labels": labels}
    if counts:
        doc["counts"] = {label: counts[label] for label in labels}
    if splits:
        doc["splits"] = splits
    path = artifacts_dir / "classes.json"
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dataset", default=DEFAULT_DATASET, help="Kaggle dataset id")
    parser.add_argument(
        "--labels",
        type=Path,
        default=REPO_ROOT / "ml_workspace" / "labels.json",
        help="semantic label table (default: %(default)s)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=REPO_ROOT / "ml_workspace" / "data",
        help="where the split manifests are written (default: %(default)s)",
    )
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        default=REPO_ROOT / "ml_workspace" / "artifacts",
        help="where classes.json is written (default: %(default)s)",
    )
    parser.add_argument(
        "--catalogue-dir",
        type=Path,
        help="an extracted styles.csv + images/ tree; skips the download entirely",
    )
    parser.add_argument(
        "--download-dir",
        type=Path,
        default=REPO_ROOT / "ml_workspace" / "data" / "download",
        help="where the Kaggle .zip lands (default: %(default)s)",
    )
    parser.add_argument("--seed", type=int, default=20261015, help="split seed")
    parser.add_argument("--val-frac", type=float, default=0.1)
    parser.add_argument("--test-frac", type=float, default=0.1)
    parser.add_argument(
        "--labels-only",
        action="store_true",
        help="write classes.json from labels.json's keep flags; no dataset needed",
    )
    args = parser.parse_args(argv)

    try:
        entries = read_labels(args.labels, args.dataset)
        if args.val_frac <= 0 or args.test_frac <= 0 or args.val_frac + args.test_frac >= 1:
            raise PrepError("--val-frac and --test-frac must be > 0 and sum to < 1")
        classes = [entry["label"] for entry in entries if entry.get("keep")]
        if not classes:
            raise PrepError(f"{args.labels}: no keep:true labels for {args.dataset!r}")

        if args.labels_only:
            path = write_classes(
                args.artifacts_dir,
                args.dataset,
                "labels.json keep:true entries, in labels.json order (catalogue frequency)",
                classes,
            )
            print(f"prepare_data: wrote {path} ({len(classes)} classes)")
            return 0

        catalogue_dir = args.catalogue_dir
        if catalogue_dir is None:
            credentials = kaggle_credentials()
            if credentials is None:
                raise PrepError(
                    "no Kaggle token found: expected "
                    f"{Path.home() / '.kaggle' / 'kaggle.json'} or KAGGLE_USERNAME + KAGGLE_KEY. "
                    "Download a token from https://www.kaggle.com/settings/account, or run "
                    "with --catalogue-dir pointing at an already extracted dataset. "
                    "`--labels-only` writes classes.json without any dataset."
                )
            print(f"prepare_data: using Kaggle token from {credentials}")
            catalogue_dir = args.download_dir / "catalogue"
            archive = download_catalogue(args.dataset, args.download_dir)
            extract_catalogue(archive, catalogue_dir, set(classes))
        else:
            print(f"prepare_data: reading catalogue at {catalogue_dir}")

        rows = read_catalogue(catalogue_dir, classes)
        splits = stratified_split(rows, args.seed, args.val_frac, args.test_frac)
        summary = write_manifests(args.data_dir, splits)
        path = write_classes(
            args.artifacts_dir,
            args.dataset,
            f"{args.dataset} styles.csv filtered by labels.json keep:true, seed {args.seed}",
            classes,
            counts=dict(Counter(row[2] for row in rows)),
            splits={name: len(rows_in_split) for name, rows_in_split in splits.items()},
        )
        print(f"prepare_data: wrote {path} ({len(classes)} classes)")
        print(
            "prepare_data: split totals "
            + ", ".join(f"{name} {count}" for name, count in summary["totals"].items())
        )
        for name in ("train", "val", "test"):
            print(f"prepare_data: {args.data_dir / f'{name}.csv'}")
        return 0
    except PrepError as exc:
        print(f"prepare_data: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"prepare_data: kaggle CLI failed with exit code {exc.returncode}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
