#!/usr/bin/env python3
"""Turn the Roboflow CFPD export into a YOLO tree with the app's five Categories.

The export (`Outfit analysis.v1i.yolov8.zip`) is 2,682 CFPD street photographs — garments on a
person, the domain ADR-0012 makes the scan contract — with ten classes. The app's detector only
knows five Categories, so this script is the only place that mapping lives, and it refuses an
export whose class names have changed instead of guessing.

    python ml_workspace/scripts/cfpd_to_yolo.py
    python ml_workspace/scripts/cfpd_to_yolo.py --zip "C:/Users/me/Downloads/Outfit analysis.v1i.yolov8.zip"

Writes `<out>/{train,val,test}/{images,labels}` plus `manifest.json` (source hash, class counts,
licence note). The licence is the reason the manifest exists: Kaggle lists this set as "Unknown",
its content comes from CFPD (Liu et al., 2014), so it is coursework data, not something to ship.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ZIP = Path.home() / "Downloads" / "Outfit analysis.v1i.yolov8.zip"
DEFAULT_OUT = REPO_ROOT / "ml_workspace" / "data" / "cfpd_yolo"

#: Roboflow class -> the app's Category, same vocabulary as `detectorCategories` in the Dart.
CLASS_TO_CATEGORY = {
    "bag": "Accessories",
    "sunglass": "Accessories",
    "hat": "Accessories",
    "dress": "Tops",
    "shirt": "Tops",
    "jacket": "Outerwear",
    "pants": "Bottoms",
    "shorts": "Bottoms",
    "skirt": "Bottoms",
    "shoe": "Shoes",
}
CATEGORIES = ["Tops", "Bottoms", "Outerwear", "Shoes", "Accessories"]
SPLIT_NAMES = {"train": "train", "valid": "val", "test": "test"}


class ConvertError(Exception):
    """A condition that would produce a misleading tree."""


def read_class_names(archive: zipfile.ZipFile) -> list[str]:
    """Roboflow writes `names: [...]` on one line; other exports write a `- name` list."""
    text = archive.read("data.yaml").decode("utf-8")
    names: list[str] = []
    inline = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("names:") and "[" in stripped:
            inside = stripped.split("[", 1)[1].split("]", 1)[0]
            names = [part.strip().strip("'\"") for part in inside.split(",") if part.strip()]
            inline = True
            continue
        if not inline and stripped.startswith("- "):
            names.append(stripped[2:].strip().strip("'\""))
    if not names:
        raise ConvertError("data.yaml carries no `names` list")
    return names


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--force", action="store_true", help="rebuild the output tree")
    args = parser.parse_args(argv)

    try:
        if not args.zip.is_file():
            raise ConvertError(f"{args.zip} does not exist; download the Roboflow export first")
        if args.force and args.out.exists():
            shutil.rmtree(args.out)

        with zipfile.ZipFile(args.zip) as archive:
            names = read_class_names(archive)
            unknown = [name for name in names if name not in CLASS_TO_CATEGORY]
            if unknown:
                raise ConvertError(
                    f"classes {unknown} have no Category mapping; extend CLASS_TO_CATEGORY "
                    "before running this again"
                )
            index_to_category = {
                index: CLASS_TO_CATEGORY[name] for index, name in enumerate(names)
            }

            counts: dict[str, collections.Counter] = {}
            images_written = 0
            for source_split, target_split in SPLIT_NAMES.items():
                image_entries = [
                    entry
                    for entry in archive.namelist()
                    if entry.startswith(f"{source_split}/images/")
                    and entry.lower().endswith((".jpg", ".jpeg", ".png"))
                ]
                if not image_entries:
                    raise ConvertError(f"split {source_split} holds no images")

                images_dir = args.out / target_split / "images"
                labels_dir = args.out / target_split / "labels"
                images_dir.mkdir(parents=True, exist_ok=True)
                labels_dir.mkdir(parents=True, exist_ok=True)
                counts[target_split] = collections.Counter()

                for entry in sorted(image_entries):
                    stem = Path(entry).stem
                    label_entry = f"{source_split}/labels/{stem}.txt"
                    rows = []
                    if label_entry in archive.namelist():
                        for line in archive.read(label_entry).decode("utf-8").splitlines():
                            parts = line.split()
                            if len(parts) != 5:
                                continue
                            category = index_to_category[int(parts[0])]
                            rows.append(f"{CATEGORIES.index(category)} " + " ".join(parts[1:]))
                            counts[target_split][category] += 1
                    if not rows:
                        continue
                    (labels_dir / f"{stem}.txt").write_text("\n".join(rows) + "\n", encoding="utf-8")
                    (images_dir / Path(entry).name).write_bytes(archive.read(entry))
                    images_written += 1

        data_yaml = args.out / "data.yaml"
        data_yaml.write_text(
            "path: {}\ntrain: train/images\nval: val/images\ntest: test/images\n\nnames:\n".format(
                args.out.resolve().as_posix()
            )
            + "".join(f"  {index}: {name}\n" for index, name in enumerate(CATEGORIES)),
            encoding="utf-8",
        )

        manifest = {
            "version": 1,
            "source": "Outfit analysis.v1i.yolov8.zip (Roboflow workspace object-detection-90cw0, "
                      "project outfit-analysis, version 1)",
            "source_sha256": hashlib.sha256(args.zip.read_bytes()).hexdigest(),
            "upstream": "CFPD — Liu et al., Fashion Parsing with Weak Color-Category Labels (2014), "
                        "repackaged for detection",
            "licence": "Kaggle lists this set as Unknown; CFPD is a research dataset. Coursework "
                       "only, not for redistribution (docs/adr/0007).",
            "mapping": CLASS_TO_CATEGORY,
            "classes": CATEGORIES,
            "images": images_written,
            "boxes_per_split": {split: dict(sorted(counter.items())) for split, counter in counts.items()},
        }
        (args.out / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

        print(f"classes {len(CATEGORIES)}: {', '.join(CATEGORIES)}")
        for split, counter in counts.items():
            total = sum(counter.values())
            detail = ", ".join(f"{name} {count}" for name, count in sorted(counter.items()))
            print(f"{split:<6} {total:6d} boxes  {detail}")
        print(f"written {args.out}")
        return 0
    except ConvertError as exc:
        print(f"cfpd_to_yolo: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
