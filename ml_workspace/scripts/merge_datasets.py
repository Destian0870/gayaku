#!/usr/bin/env python3
"""Merge the two garment sources into one ImageFolder the classifier can train on.

    # build the tree, the manifests and the class list
    python ml_workspace/scripts/merge_datasets.py

    # look before you leap: 40 photographs per class, copies, outside the repo
    python ml_workspace/scripts/merge_datasets.py --limit-per-class 40 --link copy --out .amp/in/scratch

    # the other side of the duplicate-label decision
    python ml_workspace/scripts/merge_datasets.py --prefer-source cc0 --force

Two sources, one class list (`docs/adr/0008-merge-the-two-training-sources.md`):

    alexeygrigorev/clothing-dataset-small   the CC0 set the bootstrap model ships from: 10
                                            English folders, and the only source with Shoes
                                            and Hat. Ships its own train/validation/test.
    ryanbadai/clothes-dataset               `Clothes_Dataset/`: 15 Indonesian folders of 500
                                            listing photographs, no split.

The two overlap far more than ADR-0007 assumed: 1,412 photographs appear in both, 1,401 of
them as the same picture resized (the CC0 clone caps the long side at 400 px,
Clothes_Dataset uses 720x1280). Concatenating them would put a photograph in train from one
source and in test from the other, and the test accuracy would measure memorisation. So the
merge deduplicates first:

* identical bytes (sha256), or the same picture at another size (same basename or the same
  64-bit dHash, plus a 16x16 greyscale signature within SIGNATURE_MAX_DIFF) form one group;
* one member of a group survives. When the members disagree about the class, the survivor is
  the copy from `--prefer-source` (default `clothes`: higher resolution, the Indonesian
  vocabulary the UI shows, and it keeps all 15 of its classes at 500);
* a group that disagrees with itself inside one source is ambiguous rather than decidable,
  so every member is dropped and the group is listed in `conflicts.csv`.

Splits are decided per source folder, never per photograph: the CC0 set keeps the split it
ships with, and each Clothes_Dataset class folder is shuffled once with `--seed` and cut into
train/val/test. A re-run reproduces the same assignment, and the asserts at the end refuse to
write a tree in which one photograph reached two splits.

Outputs (`--out` is git-ignored; the two committed ones are the evidence):

    <out>/manifest.csv        one row per scanned photograph -- dropped ones included -- with
                              source, sha256, phash, kept, reason, class_after and split, so
                              every decision can be audited later
    <out>/conflicts.csv       one row per member of every duplicate group
    <out>/{train,val,test}/<class>/...   symlinks (hardlinks or copies where the OS refuses)
    <out>/.merge.json         marker: options, inputs and per-folder counts; a re-run reuses
                              the tree only when all of it still matches
    yolo/artifacts/merged_dataset.json   mapping, decisions, per-class counts, assertions
    yolo/artifacts/classes_merged.json   class order in `sorted()` order -- what ultralytics
                              derives from folder names, and what gen_dart_labels.py takes

`reason` values in manifest.csv: `kept_unique`, `kept_first_of_duplicates`,
`kept_cross_source_conflict`, `dropped_exact_duplicate`, `dropped_resized_duplicate`,
`dropped_cross_source_conflict_<source>`, `dropped_intra_source_conflict_<source>`.

Only Pillow and the standard library are used, like the rest of `ml_workspace/scripts/`.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import shutil
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CC0_DIR = REPO_ROOT / "ml_workspace" / "bootstrap" / "data" / "clothing-dataset-small"
DEFAULT_CLOTHES_DIR = REPO_ROOT / "Clothes_Dataset"
DEFAULT_LABELS = REPO_ROOT / "ml_workspace" / "labels.json"
DEFAULT_OUT = REPO_ROOT / "ml_workspace" / "data" / "merged"
DEFAULT_SUMMARY = REPO_ROOT / "ml_workspace" / "yolo" / "artifacts" / "merged_dataset.json"
DEFAULT_CLASSES_OUT = REPO_ROOT / "ml_workspace" / "yolo" / "artifacts" / "classes_merged.json"

CC0_SOURCE = "cc0"
CLOTHES_SOURCE = "clothes"
SOURCES = (CC0_SOURCE, CLOTHES_SOURCE)

#: `dataset` values in labels.json that each source's class names come from.
CC0_LABELS_DATASET = "alexeygrigorev/clothing-dataset"
CLOTHES_LABELS_DATASET = "ryanbadai/clothes-dataset"

#: CC0 folder -> merged class. Seven pairs are translations into the Indonesian vocabulary;
#: `longsleeve`, `shoes` and `hat` become the three classes Clothes_Dataset does not have, so
#: their merged names are new rows in labels.json (`gayaku/merged`), which is what makes the
#: merged class list read in the same vocabulary the UI shows. `docs/adr/0008`.
CC0_TO_MERGED = {
    "t-shirt": "Kaos",
    "shirt": "Kemeja",
    "longsleeve": "Kaos_Lengan_Panjang",
    "outwear": "Jaket",
    "dress": "Gaun",
    "skirt": "Rok",
    "pants": "Celana_Panjang",
    "shorts": "Celana_Pendek",
    "shoes": "Sepatu",
    "hat": "Topi",
}

#: The CC0 clone's split directories -> the split names ultralytics expects.
CC0_SPLIT_DIRS = {"train": "train", "validation": "val", "test": "test"}
SPLITS = ("train", "val", "test")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}

#: Two images are the same picture at another size when their 16x16 greyscale signatures
#: differ by less than this, on average, over 0..255. Measured on the 1,412 photographs the
#: two sources share: 1,401 pairs sit at or below 3, and unrelated photographs sit near 30.
SIGNATURE_SIZE = 16
SIGNATURE_MAX_DIFF = 8.0

#: dHash is 8x8 comparisons -> a 64-bit hash, printed as 16 hex characters.
PHASH_HEIGHT = 8

MANIFEST_COLUMNS = (
    "source",
    "source_folder",
    "source_path",
    "class_before",
    "class_after",
    "sha256",
    "phash",
    "kept",
    "reason",
    "split",
    "link",
)
CONFLICT_COLUMNS = (
    "group",
    "kind",
    "kept",
    "reason",
    "source",
    "source_folder",
    "source_path",
    "class_before",
    "class_after",
    "sha256",
    "phash",
)


class MergeError(Exception):
    """A condition that makes the merged tree untrustworthy."""


@dataclass
class Photo:
    source: str
    source_folder: str
    path: Path
    class_after: str
    sha256: str
    phash: int
    signature: bytes
    split: str | None = None
    kept: bool = True
    reason: str = "kept_unique"
    group: int = -1
    link: Path | None = None

    @property
    def class_before(self) -> str:
        return self.source_folder

    @property
    def basename(self) -> str:
        return self.path.stem


@dataclass
class Group:
    """One photograph, however many files and re-encodings it exists as."""

    members: list[Photo] = field(default_factory=list)

    @property
    def classes(self) -> set[str]:
        return {member.class_after for member in self.members}


def read_label_table(path: Path) -> dict[str, dict]:
    """`label -> {category, name, keep, datasets}`, rejecting contradictory rows.

    The same label string may appear once per dataset (`Shorts` is both a catalogue and a CC0
    label) as long as the rows agree; `gen_dart_labels.py` enforces the same rule.
    """
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise MergeError(f"{path} does not exist") from exc
    except json.JSONDecodeError as exc:
        raise MergeError(f"{path} is not valid JSON: {exc}") from exc
    entries = doc.get("labels")
    if not isinstance(entries, list) or not entries:
        raise MergeError(f"{path}: expected a non-empty 'labels' list")
    table: dict[str, dict] = {}
    for entry in entries:
        try:
            label, category, name, dataset = (
                entry["label"],
                entry["category"],
                entry["name"],
                entry["dataset"],
            )
        except (TypeError, KeyError) as exc:
            raise MergeError(f"{path}: malformed entry {entry!r}") from exc
        previous = table.get(label)
        if previous and (previous["category"], previous["name"]) != (category, name):
            raise MergeError(
                f"{path}: {label!r} maps to both "
                f"({previous['category']}, {previous['name']!r}) and ({category}, {name!r}); "
                "labels shared by two datasets must agree"
            )
        row = table.setdefault(
            label, {"category": category, "name": name, "keep": False, "datasets": set()}
        )
        row["datasets"].add(dataset)
        row["keep"] = row["keep"] or bool(entry.get("keep"))
    return table


def image_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        raise MergeError(f"{directory} does not exist")
    files = sorted(
        (path for path in directory.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES),
        key=lambda path: path.name,
    )
    if not files:
        raise MergeError(f"{directory} holds no photographs")
    return files


def source_folders(source_dir: Path, split_dirs: dict[str, str] | None = None) -> set[str]:
    """Class folder names a source offers -- from `train/` when it ships a split."""
    root = source_dir / "train" if split_dirs else source_dir
    if not root.is_dir():
        raise MergeError(f"{root} does not exist")
    return {entry.name for entry in root.iterdir() if entry.is_dir()}


def resolve_class_table(
    labels: dict[str, dict], cc0_dir: Path, clothes_dir: Path
) -> tuple[dict[str, str], dict[str, str]]:
    """`(cc0 folder -> merged class, clothes folder -> merged class)`, or raise.

    A folder with no `keep: true` entry in labels.json is refused rather than skipped: the
    codegen would later ship a class it cannot name. A kept label with no folder is reported,
    so a renamed or half-downloaded dataset does not pass as complete.
    """
    clothes_folders = source_folders(clothes_dir)
    unknown = sorted(folder for folder in clothes_folders if not labels.get(folder, {}).get("keep"))
    if unknown:
        raise MergeError(
            f"{clothes_dir}: folders with no keep:true entry in labels.json: "
            + ", ".join(repr(folder) for folder in unknown)
        )
    clothes_table = {folder: folder for folder in sorted(clothes_folders)}

    cc0_folders = source_folders(cc0_dir, CC0_SPLIT_DIRS)
    unmapped = sorted(folder for folder in cc0_folders if folder not in CC0_TO_MERGED)
    if unmapped:
        raise MergeError(
            f"{cc0_dir}: folders with no entry in CC0_TO_MERGED: "
            + ", ".join(repr(folder) for folder in unmapped)
            + " -- map them before merging, or the merged class list changes silently"
        )
    cc0_table = {folder: CC0_TO_MERGED[folder] for folder in sorted(cc0_folders)}

    merged = sorted(set(cc0_table.values()) | set(clothes_table.values()))
    for cls in merged:
        entry = labels.get(cls)
        if entry is None:
            raise MergeError(
                f"merged class {cls!r} has no entry in labels.json -- add it with a Category "
                "and an Indonesian name before training on it"
            )
        if not entry["keep"]:
            raise MergeError(f"merged class {cls!r} is keep:false in labels.json")
        if not entry["category"] or not entry["name"]:
            raise MergeError(f"merged class {cls!r} has no Category or Indonesian name")

    absent = sorted(
        label
        for label, entry in labels.items()
        if entry["keep"]
        and CLOTHES_LABELS_DATASET in entry["datasets"]
        and label not in clothes_table
    )
    if absent:
        print(
            "merge_datasets: note: labels.json keeps these Clothes_Dataset labels that no "
            f"folder provides: {', '.join(absent)}"
        )
    return cc0_table, clothes_table


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fingerprints(path: Path) -> tuple[int, bytes]:
    """`(64-bit dHash, 16x16 greyscale signature)` for one photograph.

    The dHash is what the manifest records and what the split assert compares; the signature
    is the tie-breaker that keeps two different garments which happen to share a dHash from
    being called the same photograph.
    """
    with Image.open(path) as image:
        grey = image.convert("L")
        wide = grey.resize((PHASH_HEIGHT + 1, PHASH_HEIGHT), Image.BILINEAR)
        small = grey.resize((SIGNATURE_SIZE, SIGNATURE_SIZE), Image.BILINEAR)
    rows = wide.tobytes()
    phash = 0
    for y in range(PHASH_HEIGHT):
        offset = y * (PHASH_HEIGHT + 1)
        for x in range(PHASH_HEIGHT):
            phash = (phash << 1) | int(rows[offset + x] > rows[offset + x + 1])
    return phash, small.tobytes()


def signature_distance(left: bytes, right: bytes) -> float:
    return sum(abs(a - b) for a, b in zip(left, right)) / len(left)


def make_photo(source: str, folder: str, path: Path, cls: str, split: str | None) -> Photo:
    phash, signature = fingerprints(path)
    return Photo(
        source=source,
        source_folder=folder,
        path=path,
        class_after=cls,
        sha256=sha256_file(path),
        phash=phash,
        signature=signature,
        split=split,
    )


def scan(
    cc0_dir: Path,
    clothes_dir: Path,
    cc0_table: dict[str, str],
    clothes_table: dict[str, str],
    limit_per_class: int = 0,
) -> list[Photo]:
    """Every photograph in both sources, hashed, in a stable order."""
    photos: list[Photo] = []
    for folder, cls in cc0_table.items():
        for split_dir, split in CC0_SPLIT_DIRS.items():
            files = image_files(cc0_dir / split_dir / folder)
            if limit_per_class:
                files = files[:limit_per_class]
            photos.extend(make_photo(CC0_SOURCE, folder, path, cls, split) for path in files)
        print(f"merge_datasets: hashed cc0/{folder} ({len(photos)} so far)")
    for folder, cls in clothes_table.items():
        files = image_files(clothes_dir / folder)
        if limit_per_class:
            files = files[:limit_per_class]
        photos.extend(make_photo(CLOTHES_SOURCE, folder, path, cls, None) for path in files)
        print(f"merge_datasets: hashed clothes/{folder} ({len(photos)} so far)")
    return photos


def folder_file_counts(
    cc0_dir: Path, clothes_dir: Path, cc0_table: dict[str, str], clothes_table: dict[str, str]
) -> dict[str, int]:
    """How many photographs each folder holds, without opening any of them.

    The marker uses this so a re-run notices when a dataset gained or lost files; hashing to
    find out would defeat the point of the marker.
    """
    counts: dict[str, int] = {}
    for folder in cc0_table:
        total = 0
        for split_dir in CC0_SPLIT_DIRS:
            directory = cc0_dir / split_dir / folder
            if directory.is_dir():
                total += sum(1 for path in directory.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES)
        counts[f"cc0/{folder}"] = total
    for folder in clothes_table:
        directory = clothes_dir / folder
        if directory.is_dir():
            counts[f"clothes/{folder}"] = sum(
                1 for path in directory.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES
            )
    return dict(sorted(counts.items()))


class Groups:
    """Union-find over photographs; a group's id is its lowest member index."""

    def __init__(self, count: int) -> None:
        self._parent = list(range(count))

    def find(self, index: int) -> int:
        while self._parent[index] != index:
            self._parent[index] = self._parent[self._parent[index]]
            index = self._parent[index]
        return index

    def union(self, left: int, right: int) -> None:
        a, b = self.find(left), self.find(right)
        if a != b:
            self._parent[max(a, b)] = min(a, b)


def group_photographs(photos: list[Photo]) -> list[Group]:
    """One group per photograph, however many files and re-encodings it exists as."""
    union = Groups(len(photos))
    by_sha: dict[str, int] = {}
    by_basename: dict[str, list[int]] = defaultdict(list)
    by_phash: dict[int, list[int]] = defaultdict(list)
    for index, photo in enumerate(photos):
        if photo.sha256 in by_sha:
            union.union(by_sha[photo.sha256], index)
        else:
            by_sha[photo.sha256] = index
        by_basename[photo.basename].append(index)
        by_phash[photo.phash].append(index)

    def join_near(candidates: list[int]) -> None:
        for position, left in enumerate(candidates):
            for right in candidates[position + 1 :]:
                if (
                    signature_distance(photos[left].signature, photos[right].signature)
                    <= SIGNATURE_MAX_DIFF
                ):
                    union.union(left, right)

    for candidates in by_basename.values():
        if len(candidates) > 1:
            join_near(candidates)
    for candidates in by_phash.values():
        if len(candidates) > 1:
            join_near(candidates)

    buckets: dict[int, Group] = {}
    for index, photo in enumerate(photos):
        root = union.find(index)
        photo.group = root
        buckets.setdefault(root, Group()).members.append(photo)
    return [buckets[root] for root in sorted(buckets)]


def preference(photo: Photo, prefer_source: str) -> tuple:
    """Sort key for the survivor of a group: preferred source first, then the larger file.

    A 720x1280 listing shot carries more signal at 224 px than a 400 px cap, which is the same
    reasoning behind `--prefer-source clothes`; size and path break ties so a re-run keeps the
    same survivor.
    """
    return (
        0 if photo.source == prefer_source else 1,
        -photo.path.stat().st_size,
        photo.source,
        str(photo.path),
    )


def resolve_groups(groups: list[Group], prefer_source: str) -> None:
    """Decide which member of each group survives, and why."""
    for group in groups:
        if len(group.members) == 1:
            continue
        per_source: dict[str, set[str]] = defaultdict(set)
        for member in group.members:
            per_source[member.source].add(member.class_after)
        if any(len(classes) > 1 for classes in per_source.values()):
            for member in group.members:
                member.kept = False
                member.reason = f"dropped_intra_source_conflict_{member.source}"
            continue
        ordered = sorted(group.members, key=lambda photo: preference(photo, prefer_source))
        survivor, rest = ordered[0], ordered[1:]
        across_sources = len(group.classes) > 1
        survivor.reason = "kept_cross_source_conflict" if across_sources else "kept_first_of_duplicates"
        for member in rest:
            member.kept = False
            if across_sources and member.source != survivor.source:
                member.reason = f"dropped_cross_source_conflict_{member.source}"
            elif member.sha256 == survivor.sha256:
                member.reason = "dropped_exact_duplicate"
            else:
                member.reason = "dropped_resized_duplicate"


def assign_clothes_splits(
    photos: list[Photo], seed: int, val_frac: float, test_frac: float
) -> None:
    """Cut each kept Clothes_Dataset class folder into train/val/test, once, with `seed`.

    Per folder rather than per photograph: the CC0 set is split by its upstream author and
    cannot be redrawn, so a global shuffle would either ignore that split or leak across it.
    """
    by_class: dict[str, list[Photo]] = defaultdict(list)
    for photo in photos:
        if photo.kept and photo.source == CLOTHES_SOURCE:
            by_class[photo.class_after].append(photo)
    for cls in sorted(by_class):
        members = sorted(by_class[cls], key=lambda photo: photo.path.name)
        random.Random(f"{seed}:{cls}").shuffle(members)
        n_test = max(1, round(len(members) * test_frac))
        n_val = max(1, round(len(members) * val_frac))
        if len(members) - n_test - n_val < 1:
            raise MergeError(
                f"{cls}: {len(members)} photographs cannot fill train/val/test with "
                f"val {val_frac} and test {test_frac}"
            )
        for index, photo in enumerate(members):
            photo.split = "test" if index < n_test else "val" if index < n_test + n_val else "train"


def display_path(path: Path) -> str:
    """Repo-relative when the path is inside the checkout, absolute otherwise.

    The manifest and conflicts log stay absolute -- they are git-ignored audit material for the
    machine that ran the merge. The committed summary is not, and a `D:\\repo\\...` or
    `/kaggle/input/...` prefix in it only makes the file harder to read.
    """
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def assert_splits(
    photos: list[Photo], groups: list[Group], smoke: bool
) -> tuple[dict, list[dict]]:
    """Refuse a tree in which one photograph reached two splits.

    Fatal, not a warning: a leak here is discovered only after a training run that looked
    better than it was, which is the number this merge exists to keep honest. Four checks:

    * every kept photograph has a split;
    * no duplicate group has survivors in two splits;
    * no sha256 survives twice;
    * no phash -- the 64-bit dHash recorded in the manifest -- is shared by photographs in
      two splits, *unless* the 16x16 signatures prove the pictures differ. That exception is
      not laziness: 11 unrelated plain-background photographs in the CC0 clone share one
      dHash (0x0707070707070707) while sitting 14 to 25 grey levels apart, so an equality-only
      check would refuse a correct merge. Every surviving collision is counted in the summary.
    """
    kept = [photo for photo in photos if photo.kept]
    unassigned = [str(photo.path) for photo in kept if photo.split not in SPLITS]
    if unassigned:
        raise MergeError(f"{len(unassigned)} kept photographs have no split, e.g. {unassigned[0]}")

    for group in groups:
        surviving = [member for member in group.members if member.kept]
        splits = {member.split for member in surviving}
        if len(splits) > 1:
            raise MergeError(
                "duplicate group reached several splits "
                f"({', '.join(sorted(str(split) for split in splits))}): "
                + ", ".join(str(member.path) for member in surviving)
            )

    seen_sha: dict[str, str] = {}
    for photo in kept:
        if photo.sha256 in seen_sha:
            raise MergeError(
                f"sha256 {photo.sha256[:12]} survives twice: "
                f"{seen_sha[photo.sha256]} and {photo.path}"
            )
        seen_sha[photo.sha256] = str(photo.path)

    # Independent of the grouping above: every cross-source duplicate in these datasets kept
    # its filename, so a surviving basename in two splits means dedupe stopped working.
    by_basename: dict[str, list[Photo]] = defaultdict(list)
    for photo in kept:
        by_basename[photo.basename].append(photo)
    for basename, members in by_basename.items():
        if len(members) < 2 or len({member.split for member in members}) < 2:
            continue
        closest = min(
            (
                signature_distance(left.signature, right.signature)
                for position, left in enumerate(members)
                for right in members[position + 1 :]
            ),
            default=float("inf"),
        )
        if closest <= SIGNATURE_MAX_DIFF:
            raise MergeError(
                f"{basename} survives in splits "
                f"{sorted({str(member.split) for member in members})} with signatures "
                f"{closest:.1f} apart, i.e. one photograph: "
                + ", ".join(str(member.path) for member in members)
            )

    by_phash: dict[int, list[Photo]] = defaultdict(list)
    for photo in kept:
        by_phash[photo.phash].append(photo)
    collisions: list[dict] = []
    for phash, members in by_phash.items():
        if len({member.split for member in members}) < 2:
            continue
        for position, left in enumerate(members):
            for right in members[position + 1 :]:
                if left.split == right.split:
                    continue
                distance = signature_distance(left.signature, right.signature)
                if distance <= SIGNATURE_MAX_DIFF:
                    raise MergeError(
                        f"phash {phash:016x} reaches splits {left.split} and {right.split} with "
                        f"signatures {distance:.1f} apart, i.e. the same photograph: "
                        f"{left.path} and {right.path} -- dedupe missed this pair"
                    )
        collisions.append(
            {
                "phash": f"{phash:016x}",
                "photographs": len(members),
                "splits": sorted({str(member.split) for member in members}),
                "example": [display_path(member.path) for member in members[:2]],
            }
        )

    if not smoke:
        thin = []
        for cls in sorted({photo.class_after for photo in kept}):
            per_split = Counter(photo.split for photo in kept if photo.class_after == cls)
            missing = [split for split in SPLITS if not per_split.get(split)]
            if missing:
                thin.append(f"{cls} has no {', '.join(missing)}")
        if thin:
            raise MergeError("a class cannot be measured on every split: " + "; ".join(thin))

    return {
        "every_kept_photo_has_a_split": f"passed ({len(kept)} photographs)",
        "duplicate_groups_single_split": f"passed ({len(groups)} groups)",
        "sha256_unique": f"passed ({len(seen_sha)} photographs)",
        "basename_single_split": f"passed ({len(by_basename)} basenames)",
        "phash_unique_per_split": (
            f"passed ({len(by_phash)} distinct phash values, {len(collisions)} shared by "
            "different pictures and recorded in phash_collisions)"
        ),
        "every_class_on_every_split": "skipped (smoke run)" if smoke else "passed",
    }, collisions


def link_photo(source: Path, target: Path, requested: str, used: Counter) -> None:
    """Place one photograph at `target`, preferring a link over a copy."""
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise MergeError(f"{target} already exists; rerun with --force")
    if requested in {"auto", "symlink"}:
        try:
            os.symlink(source, target)
            used["symlink"] += 1
            return
        except (OSError, NotImplementedError):
            if requested == "symlink":
                raise MergeError(
                    f"cannot create a symlink at {target}; on Windows enable Developer Mode or "
                    "run with --link hardlink"
                ) from None
    if requested in {"auto", "hardlink"}:
        try:
            os.link(source, target)
            used["hardlink"] += 1
            return
        except OSError:
            if requested == "hardlink":
                raise MergeError(
                    f"cannot hardlink {source} to {target}; they are on different volumes, so "
                    "run with --link copy"
                ) from None
    shutil.copy2(source, target)
    used["copy"] += 1


def build_tree(out: Path, photos: list[Photo], link_mode: str, force: bool) -> Counter:
    """Write `{train,val,test}/<class>/...` with one link per kept photograph."""
    if force and out.exists():
        shutil.rmtree(out)
    if out.exists() and any(out.iterdir()):
        raise MergeError(f"{out} is not empty; rerun with --force to rebuild it")
    used: Counter = Counter()
    taken: set[Path] = set()
    for photo in sorted(
        (photo for photo in photos if photo.kept),
        key=lambda photo: (str(photo.split), photo.class_after, str(photo.path)),
    ):
        stem = f"{photo.source}_{photo.path.stem}"
        target = out / str(photo.split) / photo.class_after / f"{stem}{photo.path.suffix.lower()}"
        suffix = 1
        while target in taken:
            suffix += 1
            target = out / str(photo.split) / photo.class_after / f"{stem}_{suffix}{photo.path.suffix.lower()}"
        taken.add(target)
        link_photo(photo.path, target, link_mode, used)
        photo.link = target
    return used


def write_manifest(out: Path, photos: list[Photo]) -> Path:
    path = out / "manifest.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(MANIFEST_COLUMNS)
        for photo in photos:
            writer.writerow(
                [
                    photo.source,
                    photo.source_folder,
                    str(photo.path),
                    photo.class_before,
                    photo.class_after,
                    photo.sha256,
                    f"{photo.phash:016x}",
                    "1" if photo.kept else "0",
                    photo.reason,
                    photo.split if photo.kept else "",
                    str(photo.link) if photo.kept and photo.link else "",
                ]
            )
    return path


def conflict_kind(group: Group) -> str:
    per_source: dict[str, set[str]] = defaultdict(set)
    for member in group.members:
        per_source[member.source].add(member.class_after)
    if any(len(classes) > 1 for classes in per_source.values()):
        return "intra_source_label_conflict"
    if len(group.classes) > 1:
        return "cross_source_label_conflict"
    return "duplicate_same_class"


def write_conflicts(out: Path, groups: list[Group]) -> Path:
    path = out / "conflicts.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(CONFLICT_COLUMNS)
        for group in groups:
            if len(group.members) < 2:
                continue
            kind = conflict_kind(group)
            for member in sorted(group.members, key=lambda photo: (photo.source, str(photo.path))):
                writer.writerow(
                    [
                        f"g{group.members[0].group:05d}",
                        kind,
                        "1" if member.kept else "0",
                        member.reason,
                        member.source,
                        member.source_folder,
                        str(member.path),
                        member.class_before,
                        member.class_after,
                        member.sha256,
                        f"{member.phash:016x}",
                    ]
                )
    return path


def per_class_summary(photos: list[Photo], classes: list[str]) -> dict:
    """Unique surviving photographs per class, and where they come from."""
    summary: dict[str, dict] = {}
    for cls in classes:
        members = [photo for photo in photos if photo.class_after == cls and photo.kept]
        summary[cls] = {
            "unique": len(members),
            "train": sum(1 for photo in members if photo.split == "train"),
            "val": sum(1 for photo in members if photo.split == "val"),
            "test": sum(1 for photo in members if photo.split == "test"),
            "by_source": dict(sorted(Counter(photo.source for photo in members).items())),
        }
    return summary


def conflict_pairs(groups: list[Group]) -> dict[str, int]:
    """`"clothes:longsleeve -> Sweter"` style tallies, for readers of the summary."""
    tally: Counter = Counter()
    for group in groups:
        if len(group.members) < 2:
            continue
        surviving = [member for member in group.members if member.kept]
        if not surviving:
            for member in group.members:
                tally[f"{member.source}:{member.class_before} -> dropped as ambiguous"] += 1
            continue
        winner = surviving[0]
        for member in group.members:
            if member is winner or member.class_after == winner.class_after:
                continue
            tally[f"{member.source}:{member.class_before} -> {winner.class_after}"] += 1
    return dict(sorted(tally.items(), key=lambda item: (-item[1], item[0])))


DECISIONS = {
    "prefer_source": (
        "When one photograph carries different classes in the two sources, the copy from "
        "--prefer-source survives. `clothes` is the default: it keeps the 15 Clothes_Dataset "
        "classes at 500, carries the vocabulary the UI shows, and holds 2.3x the pixels of the "
        "CC0 clone. The cost is not a display detail. The largest conflict pair is `longsleeve` "
        "in CC0 against `Sweter` in Clothes_Dataset, and those two labels sit in different "
        "Categories: Longsleeve is Tops, Sweter is Outerwear. Choosing `clothes` therefore files "
        "403 long-sleeve photographs under Outerwear that CC0 would have filed under Tops, which "
        "changes the wardrobe tab and what the outfit matcher sees. `--prefer-source cc0` "
        "reverses it without a code change and leaves Sweter at 93, Kaos_Lengan_Panjang at 575."
    ),
    "keep_thin_classes": (
        "Longsleeve keeps its surviving photographs instead of being folded into Kaos. Topi "
        "ships with a comparable count today, so a thin class is a measurable weakness -- the "
        "per-class recall in the training report -- rather than a reason to delete a class the "
        "product shows."
    ),
    "ambiguous_groups": (
        "A group that disagrees with itself inside one source gets no survivor: every member is "
        "dropped and listed in conflicts.csv. Identical bytes filed under Jaket, Kemeja and "
        "Polo claim two of those labels are wrong, and picking one would invent an answer the "
        "data does not give."
    ),
    "splits": (
        "CC0 keeps the train/validation/test split it ships with; Clothes_Dataset has none, so "
        "each class folder is shuffled once with --seed and cut. Nothing is shuffled per "
        "photograph, so a re-run reproduces the same assignment and no photograph crosses a split."
    ),
    "class_names": (
        "The merged class list is the Indonesian vocabulary for all 18 classes, including the "
        "three Clothes_Dataset does not have: Kaos_Lengan_Panjang, Sepatu and Topi. Their rows "
        "in labels.json are tagged `gayaku/merged`, because the CC0 dataset itself only has the "
        "English spellings (Longsleeve, Shoes, Hat) that the bootstrap 10-class model uses. "
        "Every merged class therefore reaches the UI with the same name it would have had as a "
        "Clothes_Dataset folder, and gen_dart_labels.py needs no special case."
    ),
}


def write_summary(
    path: Path,
    photos: list[Photo],
    groups: list[Group],
    classes: list[str],
    labels: dict[str, dict],
    cc0_table: dict[str, str],
    clothes_table: dict[str, str],
    options: dict,
    used: Counter,
    assertions: dict,
    collisions: list[dict],
    inputs: dict,
) -> dict:
    clothes_classes = set(clothes_table.values())
    summary = {
        "version": 1,
        "sources": inputs,
        "mapping": {
            "cc0_to_merged": dict(sorted(CC0_TO_MERGED.items())),
            "clothes_to_merged": "identity (folder name is the class)",
        },
        "options": dict(options, link_mode_used=dict(sorted(used.items())) or {"none": 0}),
        "decisions": DECISIONS,
        "classes": {
            cls: {
                "category": labels[cls]["category"],
                "name": labels[cls]["name"],
                "label_from": (
                    CLOTHES_LABELS_DATASET if cls in clothes_classes else CC0_LABELS_DATASET
                ),
            }
            for cls in classes
        },
        "totals": {
            "scanned": len(photos),
            "kept": sum(1 for photo in photos if photo.kept),
            "groups": len(groups),
            "groups_with_several_members": sum(1 for group in groups if len(group.members) > 1),
            "by_reason": dict(sorted(Counter(photo.reason for photo in photos).items())),
            "by_source_scanned": dict(sorted(Counter(photo.source for photo in photos).items())),
            "by_source_kept": dict(
                sorted(Counter(photo.source for photo in photos if photo.kept).items())
            ),
        },
        "per_class": per_class_summary(photos, classes),
        "conflict_pairs": conflict_pairs(groups),
        "assertions": assertions,
        "phash_collisions": collisions,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def write_classes(path: Path, classes: list[str], counts: dict) -> None:
    """Class list in `sorted()` order, which is the order ultralytics derives from folders."""
    path.parent.mkdir(parents=True, exist_ok=True)
    doc = {
        "version": 1,
        "dataset": "merged",
        "source": (
            "merge_datasets.py over alexeygrigorev/clothing-dataset-small and "
            "ryanbadai/clothes-dataset; labels in sorted() order, which is the order "
            "ultralytics derives from the class folders and therefore the model's output order"
        ),
        "labels": classes,
        "counts": {cls: counts[cls]["unique"] for cls in classes},
    }
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def marker_matches(out: Path, marker: dict) -> bool:
    try:
        previous = json.loads((out / ".merge.json").read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    return previous == marker


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cc0-dir", type=Path, default=DEFAULT_CC0_DIR)
    parser.add_argument("--clothes-dir", type=Path, default=DEFAULT_CLOTHES_DIR)
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS)
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="where the ImageFolder tree and the two CSVs go (default: %(default)s)",
    )
    parser.add_argument("--summary", type=Path, default=DEFAULT_SUMMARY)
    parser.add_argument("--classes-out", type=Path, default=DEFAULT_CLASSES_OUT)
    parser.add_argument(
        "--prefer-source",
        choices=SOURCES,
        default=CLOTHES_SOURCE,
        help="whose copy and label survive a cross-source duplicate (default: %(default)s)",
    )
    parser.add_argument("--seed", type=int, default=20261022, help="Clothes_Dataset split seed")
    parser.add_argument("--val-frac", type=float, default=0.1)
    parser.add_argument("--test-frac", type=float, default=0.1)
    parser.add_argument(
        "--link",
        choices=("auto", "symlink", "hardlink", "copy"),
        default="auto",
        help="how the tree points at the photographs (default: %(default)s)",
    )
    parser.add_argument(
        "--limit-per-class",
        type=int,
        default=0,
        help="smoke test: scan at most this many photographs per folder, skip the coverage assert",
    )
    parser.add_argument(
        "--force", action="store_true", help="rebuild the output tree instead of reusing it"
    )
    args = parser.parse_args(argv)

    try:
        if args.val_frac <= 0 or args.test_frac <= 0 or args.val_frac + args.test_frac >= 1:
            raise MergeError("--val-frac and --test-frac must be > 0 and sum to < 1")
        smoke = args.limit_per_class > 0
        if smoke and args.summary == DEFAULT_SUMMARY:
            args.summary = args.out / "merged_dataset.json"
            args.classes_out = args.out / "classes_merged.json"

        labels = read_label_table(args.labels)
        cc0_table, clothes_table = resolve_class_table(labels, args.cc0_dir, args.clothes_dir)
        inputs = {
            CC0_SOURCE: {
                "dataset": CC0_LABELS_DATASET,
                "dir": display_path(args.cc0_dir),
                "splits": sorted(CC0_SPLIT_DIRS.values()),
                "folders": len(cc0_table),
            },
            CLOTHES_SOURCE: {
                "dataset": CLOTHES_LABELS_DATASET,
                "dir": display_path(args.clothes_dir),
                "splits": [],
                "folders": len(clothes_table),
            },
        }
        options = {
            "prefer_source": args.prefer_source,
            "seed": args.seed,
            "val_frac": args.val_frac,
            "test_frac": args.test_frac,
            "signature_size": SIGNATURE_SIZE,
            "signature_max_diff": SIGNATURE_MAX_DIFF,
            "link_mode_requested": args.link,
            "limit_per_class": args.limit_per_class,
        }
        marker = {
            "marker": "merge_datasets/v1",
            "options": options,
            "inputs": inputs,
            "files": folder_file_counts(args.cc0_dir, args.clothes_dir, cc0_table, clothes_table),
        }
        if not args.force and marker_matches(args.out, marker):
            print(f"merge_datasets: reusing {args.out} (marker matches; --force rebuilds it)")
            return 0

        photos = scan(args.cc0_dir, args.clothes_dir, cc0_table, clothes_table, args.limit_per_class)
        groups = group_photographs(photos)
        resolve_groups(groups, args.prefer_source)
        assign_clothes_splits(photos, args.seed, args.val_frac, args.test_frac)
        assertions, collisions = assert_splits(photos, groups, smoke)
        used = build_tree(args.out, photos, args.link, args.force)

        classes = sorted(set(cc0_table.values()) | set(clothes_table.values()))
        manifest = write_manifest(args.out, photos)
        conflicts = write_conflicts(args.out, groups)
        summary = write_summary(
            args.summary,
            photos,
            groups,
            classes,
            labels,
            cc0_table,
            clothes_table,
            options,
            used,
            assertions,
            collisions,
            inputs,
        )
        write_classes(args.classes_out, classes, summary["per_class"])
        (args.out / ".merge.json").write_text(
            json.dumps(marker, indent=2) + "\n", encoding="utf-8"
        )

        print(
            f"merge_datasets: {summary['totals']['scanned']} scanned, "
            f"{summary['totals']['kept']} unique photographs over {len(classes)} classes"
        )
        print(f"merge_datasets: {manifest}")
        print(f"merge_datasets: {conflicts}")
        print(f"merge_datasets: {args.summary}")
        print(f"merge_datasets: {args.classes_out}")
        print("merge_datasets: unique photographs per class")
        for cls in classes:
            row = summary["per_class"][cls]
            print(
                f"  {cls:18s} {row['unique']:5d}  train {row['train']:5d}  "
                f"val {row['val']:4d}  test {row['test']:4d}  {row['by_source']}"
            )
        return 0
    except MergeError as exc:
        print(f"merge_datasets: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
