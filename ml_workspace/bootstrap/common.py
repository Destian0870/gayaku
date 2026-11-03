#!/usr/bin/env python3
"""Shared helpers for the CC0 bootstrap classifier run.

Deliberately torch-free and TensorFlow-free: `fetch_dataset.py`,
`train_classifier.py` and `export_tflite.py` all import this module, and they
run in different interpreters (the training one has torch, the conversion one
has TensorFlow). Only numpy and Pillow are required here.

The bootstrap exists because `docs/adr/0003` keeps the Kaggle catalogue as the
final training set and that catalogue needs credentials this machine does not
have. `alexeygrigorev/clothing-dataset-small` (CC0) is ADR-0003's own optional
augmentation set, so it is a legitimate stand-in for proving the pipeline.
"""

from __future__ import annotations

import hashlib
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_DIR = Path(__file__).resolve().parent
DEFAULT_DATA_DIR = BOOTSTRAP_DIR / "data" / "clothing-dataset-small"
DEFAULT_LABELS = REPO_ROOT / "ml_workspace" / "labels.json"
DEFAULT_ARTIFACTS = BOOTSTRAP_DIR / "artifacts"

#: GitHub clone target — CC0, no attribution required, ~103 MB.
DATASET_ID = "alexeygrigorev/clothing-dataset-small"
DATASET_URL = "https://github.com/alexeygrigorev/clothing-dataset-small.git"

#: `dataset` field that `labels.json` tags the CC0 vocabulary with.
LABELS_DATASET_KEY = "alexeygrigorev/clothing-dataset"

SPLITS = ("train", "validation", "test")

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)

IMAGE_SUFFIXES = (".jpg", ".jpeg", ".png")


class BootstrapError(Exception):
    """Anything that would make the bootstrap run untrustworthy."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise BootstrapError(f"{path} does not exist") from exc
    except json.JSONDecodeError as exc:
        raise BootstrapError(f"{path} is not valid JSON: {exc}") from exc


def write_json(path: Path, doc: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def vocabulary(labels_path: Path) -> dict[str, dict]:
    """The CC0 vocabulary from `labels.json`: label -> {category, name, keep}."""
    doc = read_json(labels_path)
    entries = doc.get("labels")
    if not isinstance(entries, list) or not entries:
        raise BootstrapError(f"{labels_path}: expected a non-empty 'labels' list")
    vocab: dict[str, dict] = {}
    for entry in entries:
        if entry.get("dataset") != LABELS_DATASET_KEY:
            continue
        label = entry["label"]
        previous = vocab.get(label)
        if previous and (previous["category"], previous["name"]) != (
            entry["category"],
            entry["name"],
        ):
            raise BootstrapError(f"{labels_path}: contradictory rows for {label!r}")
        vocab[label] = {
            "category": entry["category"],
            "name": entry["name"],
            "keep": bool(entry.get("keep")),
        }
    if not vocab:
        raise BootstrapError(f"{labels_path}: no entries tagged {LABELS_DATASET_KEY!r}")
    return vocab


def folder_name_map(vocab: dict[str, dict]) -> dict[str, str]:
    """ImageFolder folder name -> `labels.json` label spelling.

    `clothing-dataset-small` uses lowercase folder names (`t-shirt`) while
    `labels.json` uses the dataset's JSON spelling (`T-Shirt`); the mapping is
    case-insensitive and fails loudly on a tie.
    """
    by_lower: dict[str, str] = {}
    for label in vocab:
        key = label.casefold()
        if key in by_lower and by_lower[key] != label:
            raise BootstrapError(f"label spellings collide on {label!r}")
        by_lower[key] = label
    return by_lower


def dataset_classes(data_dir: Path, vocab: dict[str, dict]) -> list[tuple[str, str]]:
    """Ordered `(folder, label)` pairs for every CC0 folder we may train on.

    Order follows `labels.json` (the same rule `prepare_data.py` uses for the
    catalogue), restricted to `keep:true` labels that actually have a folder in
    the clone. Folders with `keep:false` (junk values such as `Not sure`) are
    ignored; `train` is what defines the class list.
    """
    train_dir = data_dir / "train"
    if not train_dir.is_dir():
        raise BootstrapError(f"{train_dir} does not exist — run fetch_dataset.py first")
    folders = sorted(entry.name for entry in train_dir.iterdir() if entry.is_dir())
    by_lower = folder_name_map(vocab)
    resolved: dict[str, str] = {}
    unknown: list[str] = []
    for folder in folders:
        label = by_lower.get(folder.casefold())
        if label is None or not vocab[label]["keep"]:
            unknown.append(folder)
            continue
        resolved[folder] = label
    if unknown:
        raise BootstrapError(
            "dataset folders with no keep:true entry in labels.json: "
            + ", ".join(repr(folder) for folder in unknown)
            + " -- APPEND them to ml_workspace/labels.json or exclude the folder"
        )
    if not resolved:
        raise BootstrapError(f"{train_dir}: no usable class folders")
    ordered = [label for label in vocab if label in set(resolved.values())]
    return [(folder, label) for label in ordered for folder, value in resolved.items() if value == label]


def split_images(data_dir: Path, split: str, folders: list[str]) -> dict[str, list[Path]]:
    """`folder -> sorted image paths` for one split."""
    out: dict[str, list[Path]] = {}
    for folder in folders:
        directory = data_dir / split / folder
        if not directory.is_dir():
            raise BootstrapError(f"missing split directory {directory}")
        images = sorted(
            (path for path in directory.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES),
            key=lambda path: path.name,
        )
        if not images:
            raise BootstrapError(f"{directory} holds no images")
        out[folder] = images
    return out


def held_out_subset(
    data_dir: Path, split: str, folders: list[str], per_class: int, seed: int
) -> list[tuple[Path, str]]:
    """A deterministic `per_class`-per-class slice of `split`, as (path, folder).

    Both the PyTorch evaluation and the converted-model check use this exact
    list, so their accuracy numbers are comparable image by image.
    """
    per_folder = split_images(data_dir, split, folders)
    picked: list[tuple[Path, str]] = []
    for folder in folders:
        images = per_folder[folder]
        rng = random.Random(f"{seed}:{split}:{folder}")
        chosen = images if len(images) <= per_class else sorted(rng.sample(images, per_class))
        picked.extend((path, folder) for path in chosen)
    return sorted(picked, key=lambda item: (item[1], item[0].name))


def eval_transform(image: Image.Image, size: int = 224, resize_to: int = 256) -> np.ndarray:
    """Aspect-preserving short-side resize + centre crop, as float32 `[0,1]` HWC.

    Mirrors the torchvision evaluation pipeline (`Resize(256)`, `CenterCrop(224)`)
    closely enough that a top-1 label is comparable between PyTorch and the
    converted model. Bilinear in both, per torchvision's default.
    """
    image = image.convert("RGB")
    width, height = image.size
    scale = resize_to / min(width, height)
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    image = image.resize(new_size, Image.BILINEAR)
    left = (new_size[0] - size) // 2
    top = (new_size[1] - size) // 2
    image = image.crop((left, top, left + size, top + size))
    return np.asarray(image, dtype=np.float32) / 255.0
