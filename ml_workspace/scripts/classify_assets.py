"""Classify the app's own garment photos with the shipped classifier.

This is the sanity check that answers "does the model recognise anything, or is
it just guessing pants?" against real assets rather than the training split. It
mirrors the classifier's input exactly as `lib/logic/scan_pipeline.dart` builds
it — 224x224, RGB, `[0,1]`, with ImageNet normalisation baked into the exported
model — but skips the matting step, so for a photo whose garment fills the frame
the numbers match what the phone reports after the cutout.

Needs a Python environment with `tensorflow` (the one
`ml_workspace/bootstrap/README.md` documents for conversion); every other script
in `ml_workspace/` is dependency-light on purpose.

    python ml_workspace/scripts/classify_assets.py
    python ml_workspace/scripts/classify_assets.py --markdown
    python ml_workspace/scripts/classify_assets.py --model path/to/other.tflite

`--markdown` prints a table for pasting into a report. Remember: a label is only
as trustworthy as the class list the model was trained on — a bag photo in a
model trained without bags will still come back with a garment label.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

import numpy as np
import tensorflow as tf
from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_MODEL = REPO / "flutter_app/assets/models/garment_classifier.tflite"
DEFAULT_IMAGES = REPO / "flutter_app/assets/images"
# The list the shipped model was exported with. A different model needs its own
# list; the script refuses a mismatched pair and names the candidates.
DEFAULT_CLASSES = REPO / "ml_workspace/bootstrap/artifacts/classes.json"
LABELS = REPO / "ml_workspace/labels.json"
SIZE = 224


def label_metadata() -> dict[str, dict]:
    rows = json.loads(LABELS.read_text())["labels"]
    return {row["label"]: row for row in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", type=pathlib.Path, default=DEFAULT_MODEL)
    parser.add_argument("--images", type=pathlib.Path, default=DEFAULT_IMAGES)
    parser.add_argument("--classes", type=pathlib.Path, default=DEFAULT_CLASSES)
    parser.add_argument(
        "--markdown",
        action="store_true",
        help="print a markdown table instead of the plain one",
    )
    args = parser.parse_args()

    if not args.model.exists():
        print(f"model not found: {args.model}", file=sys.stderr)
        return 1
    digest = hashlib.sha256(args.model.read_bytes()).hexdigest()

    # The class list must be the one this model was exported with; the app
    # enforces the same pairing at load time.
    classes = json.loads(args.classes.read_text())["labels"]
    meta = label_metadata()

    interpreter = tf.lite.Interpreter(model_path=str(args.model))
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]
    width = int(out["shape"][-1])
    if width != len(classes):
        candidates = [
            path.relative_to(REPO)
            for path in REPO.glob("ml_workspace/**/classes.json")
            if len(json.loads(path.read_text())["labels"]) == width
        ]
        print(
            f"model scores {width} classes but {args.classes.relative_to(REPO)} "
            f"lists {len(classes)}.\nClass lists here that fit this model: "
            f"{', '.join(str(c) for c in candidates) or 'none — regenerate one'}",
            file=sys.stderr,
        )
        return 1
    print(
        f"model {args.model.name} sha256 {digest[:16]}… | "
        f"in {list(inp['shape'])} {np.dtype(inp['dtype']).name} | "
        f"out {list(out['shape'])} {np.dtype(out['dtype']).name} | "
        f"{len(classes)} classes\n"
    )

    photos = sorted(
        path
        for path in args.images.glob("*")
        if path.suffix.lower() in {".png", ".jpg", ".jpeg"} and not path.name.startswith(".")
    )
    if not photos:
        print(f"no photos in {args.images}", file=sys.stderr)
        return 1

    rows = []
    for path in photos:
        image = Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.BILINEAR)
        batch = (np.asarray(image, dtype=np.float32) / 255.0)[None, ...]
        interpreter.set_tensor(inp["index"], batch)
        interpreter.invoke()
        scores = interpreter.get_tensor(out["index"])[0]
        best = int(scores.argmax())
        label = classes[best]
        row = meta.get(label, {})
        rows.append(
            (path.name, label, row.get("category") or "-", row.get("name") or "-", scores[best])
        )

    if args.markdown:
        print("| Foto | Label | Category | Nama | Keyakinan |")
        print("|---|---|---|---|---|")
        for name, label, category, indonesian, score in rows:
            print(f"| `{name}` | {label} | {category} | {indonesian} | {score * 100:.1f}% |")
    else:
        for name, label, category, indonesian, score in rows:
            print(f"{name:<32} {label:<14} {category:<11} {indonesian:<20} {score * 100:5.1f}%")

    print(f"\n{len(rows)} photos classified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
