#!/usr/bin/env python3
"""Train the BOOTSTRAP garment classifier on CC0 data and write the metrics report.

NOT the final model: `docs/adr/0003` keeps the Kaggle catalogue (141 article types
mapped to the five Categories) as the training set. This run exists so the shipped
pipeline can be exercised end to end when no Kaggle credentials are available; its
data is ADR-0003's optional CC0 augmentation set,
`alexeygrigorev/clothing-dataset-small`.

    python ml_workspace/bootstrap/train_classifier.py                 # 8 epochs, CPU
    python ml_workspace/bootstrap/train_classifier.py --epochs 12 --lr 1e-3

Writes, under `ml_workspace/bootstrap/artifacts/`:
  classes.json             the class list actually trained (index = model output index)
  garment_classifier.pt    the checkpoint `export_tflite.py` reads
  report.md                measured metrics + confusion matrix + exact command/environment
  subset_predictions.json  PyTorch predictions on the shared held-out subset, so the
                           converted-model check can compare top-1 image by image

Class order is `labels.json`'s CC0 order restricted to the folders present in the
clone — the same rule `prepare_data.py` uses for the catalogue, so both paths agree.
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torchvision
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms
from PIL import Image

from common import (
    DATASET_ID,
    DEFAULT_ARTIFACTS,
    DEFAULT_DATA_DIR,
    DEFAULT_LABELS,
    IMAGENET_MEAN,
    IMAGENET_STD,
    BootstrapError,
    dataset_classes,
    held_out_subset,
    read_json,
    sha256_file,
    split_images,
    vocabulary,
    write_json,
)

TRAIN_SIZE = 224
RESIZE_TO = 256


class NormalizedClassifier(nn.Module):
    """MobileNetV3-small with ImageNet normalisation baked into the graph.

    Callers feed raw `[0,1]` NCHW pixels; the first ops of the exported ONNX/TFLite
    graph are the subtraction and division, which is what the Dart side expects
    (see `ml_workspace/README.md`).
    """

    def __init__(self, num_classes: int, pretrained: bool = True) -> None:
        super().__init__()
        weights = models.MobileNet_V3_Small_Weights.IMAGENET1K_V1 if pretrained else None
        backbone = models.mobilenet_v3_small(weights=weights)
        in_features = backbone.classifier[-1].in_features
        backbone.classifier[-1] = nn.Linear(in_features, num_classes)
        self.backbone = backbone
        self.num_classes = num_classes
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.backbone((x - self.mean) / self.std)


class ImagePaths(Dataset):
    def __init__(self, items: list[tuple[Path, int]], transform) -> None:
        self.items = items
        self.transform = transform

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, index: int):
        path, label = self.items[index]
        with Image.open(path) as image:
            tensor = self.transform(image.convert("RGB"))
        return tensor, label


def train_transform() -> transforms.Compose:
    return transforms.Compose(
        [
            transforms.Resize(RESIZE_TO),
            transforms.RandomCrop(TRAIN_SIZE),
            transforms.RandomHorizontalFlip(),
            transforms.RandomRotation(10),
            transforms.ColorJitter(0.2, 0.2, 0.2, 0.02),
            transforms.ToTensor(),
        ]
    )


def eval_transform_torch() -> transforms.Compose:
    return transforms.Compose(
        [
            transforms.Resize(RESIZE_TO),
            transforms.CenterCrop(TRAIN_SIZE),
            transforms.ToTensor(),
        ]
    )


def build_items(data_dir: Path, split: str, folders: list[str], index: dict[str, int]):
    images = split_images(data_dir, split, folders)
    return [(path, index[folder]) for folder in folders for path in images[folder]]


@torch.no_grad()
def evaluate(model: NormalizedClassifier, loader: DataLoader, num_classes: int):
    model.eval()
    confusion = np.zeros((num_classes, num_classes), dtype=np.int64)
    for inputs, targets in loader:
        predictions = model(inputs).argmax(dim=1)
        for truth, guess in zip(targets.tolist(), predictions.tolist()):
            confusion[truth, guess] += 1
    total = int(confusion.sum())
    accuracy = float(np.trace(confusion) / total) if total else 0.0
    return accuracy, confusion


@torch.no_grad()
def predict_paths(
    model: NormalizedClassifier, items: list[tuple[Path, str]], folder_index: dict[str, int]
):
    """Predict the shared held-out subset with the torchvision eval pipeline."""
    model.eval()
    out = []
    for path, folder in items:
        with Image.open(path) as image:
            tensor = eval_transform_torch()(image.convert("RGB")).unsqueeze(0)
        probabilities = torch.softmax(model(tensor), dim=1)[0]
        index = int(probabilities.argmax())
        out.append(
            {
                "image": path.as_posix(),
                "true": folder,
                "pred_index": index,
                "confidence": float(probabilities[index]),
                "true_index": folder_index[folder],
            }
        )
    return out


def markdown_confusion(confusion: np.ndarray, labels: list[str]) -> str:
    header = "| true \\ pred | " + " | ".join(labels) + " | recall |"
    divider = "| --- | " + " | ".join("---" for _ in labels) + " | --- |"
    lines = [header, divider]
    for row, label in enumerate(labels):
        counts = [str(int(value)) for value in confusion[row]]
        total = int(confusion[row].sum())
        recall = f"{confusion[row, row] / total:.3f}" if total else "n/a"
        lines.append(f"| **{label}** | " + " | ".join(counts) + f" | {recall} |")
    return "\n".join(lines)


def markdown_per_class(confusion: np.ndarray, labels: list[str]) -> str:
    lines = ["| class | support | correct | recall |", "| --- | --- | --- | --- |"]
    for row, label in enumerate(labels):
        total = int(confusion[row].sum())
        correct = int(confusion[row, row])
        recall = f"{correct / total:.3f}" if total else "n/a"
        lines.append(f"| {label} | {total} | {correct} | {recall} |")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR, help="%(default)s")
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS, help="%(default)s")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_ARTIFACTS, help="%(default)s")
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--threads", type=int, default=0, help="torch CPU threads (0 = default)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--subset-per-class", type=int, default=20)
    parser.add_argument("--no-pretrained", action="store_true", help="train from scratch")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args(argv)

    started = time.time()
    try:
        vocab = vocabulary(args.labels)
        pairs = dataset_classes(args.data_dir, vocab)
        folders = [folder for folder, _ in pairs]
        labels = [label for _, label in pairs]
        index = {folder: position for position, folder in enumerate(folders)}
        if not args.data_dir.is_dir():
            raise BootstrapError(f"{args.data_dir} does not exist — run fetch_dataset.py first")

        torch.manual_seed(args.seed)
        np.random.seed(args.seed)
        if args.threads:
            torch.set_num_threads(args.threads)
        device = torch.device(args.device)

        train_items = build_items(args.data_dir, "train", folders, index)
        val_items = build_items(args.data_dir, "validation", folders, index)
        test_items = build_items(args.data_dir, "test", folders, index)

        train_loader = DataLoader(
            ImagePaths(train_items, train_transform()),
            batch_size=args.batch_size,
            shuffle=True,
            num_workers=args.workers,
            drop_last=False,
            generator=torch.Generator().manual_seed(args.seed),
        )
        eval_loader = lambda items: DataLoader(  # noqa: E731
            ImagePaths(items, eval_transform_torch()),
            batch_size=args.batch_size,
            shuffle=False,
            num_workers=args.workers,
        )

        model = NormalizedClassifier(len(labels), pretrained=not args.no_pretrained).to(device)
        optimizer = torch.optim.AdamW(
            model.parameters(), lr=args.lr, weight_decay=args.weight_decay
        )
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
        criterion = nn.CrossEntropyLoss()

        best_accuracy, best_state, best_epoch = -1.0, None, 0
        history = []
        for epoch in range(1, args.epochs + 1):
            epoch_started = time.time()
            model.train()
            running, seen = 0.0, 0
            for inputs, targets in train_loader:
                inputs, targets = inputs.to(device), targets.to(device)
                optimizer.zero_grad(set_to_none=True)
                loss = criterion(model(inputs), targets)
                loss.backward()
                optimizer.step()
                running += float(loss.detach()) * inputs.size(0)
                seen += inputs.size(0)
            scheduler.step()
            val_accuracy, _ = evaluate(model, eval_loader(val_items), len(labels))
            history.append(
                {
                    "epoch": epoch,
                    "train_loss": running / max(seen, 1),
                    "val_accuracy": val_accuracy,
                    "seconds": time.time() - epoch_started,
                }
            )
            print(
                f"epoch {epoch:>2}/{args.epochs}  loss {running / max(seen, 1):.4f}  "
                f"val {val_accuracy:.4f}  ({history[-1]['seconds']:.0f}s)",
                flush=True,
            )
            if val_accuracy > best_accuracy:
                best_accuracy, best_epoch = val_accuracy, epoch
                best_state = {key: value.detach().clone() for key, value in model.state_dict().items()}

        if best_state is None:
            raise BootstrapError("training produced no checkpoint")
        model.load_state_dict(best_state)
        print(f"best epoch {best_epoch} (val {best_accuracy:.4f})")

        val_accuracy, val_confusion = evaluate(model, eval_loader(val_items), len(labels))
        test_accuracy, test_confusion = evaluate(model, eval_loader(test_items), len(labels))

        subset = held_out_subset(
            args.data_dir, "test", folders, args.subset_per_class, args.seed
        )
        subset_predictions = predict_paths(model, subset, index)
        subset_correct = sum(
            1 for row in subset_predictions if row["pred_index"] == row["true_index"]
        )
        subset_accuracy = subset_correct / len(subset_predictions)

        args.out_dir.mkdir(parents=True, exist_ok=True)
        write_json(
            args.out_dir / "classes.json",
            {
                "version": 1,
                "dataset": DATASET_ID,
                "source": (
                    "labels.json CC0 keep:true entries, in labels.json order, restricted to the "
                    "class folders present in the clone; index = exported model output index"
                ),
                "labels": labels,
            },
        )
        torch.save(
            {"model": model.state_dict(), "labels": labels, "num_classes": len(labels)},
            args.out_dir / "garment_classifier.pt",
        )
        write_json(
            args.out_dir / "subset_predictions.json",
            {
                "split": "test",
                "per_class": args.subset_per_class,
                "seed": args.seed,
                "torch_accuracy": subset_accuracy,
                "predictions": subset_predictions,
            },
        )

        dataset_summary = {}
        summary_path = args.data_dir.parent / "dataset_summary.json"
        if summary_path.is_file():
            dataset_summary = read_json(summary_path)

        command = "python ml_workspace/bootstrap/train_classifier.py " + " ".join(
            _quote(item) for item in (argv if argv is not None else sys.argv[1:])
        )
        report = _render_report(
            args=args,
            command=command.strip(),
            labels=labels,
            pairs=pairs,
            vocab=vocab,
            history=history,
            best_epoch=best_epoch,
            val_accuracy=val_accuracy,
            test_accuracy=test_accuracy,
            val_confusion=val_confusion,
            test_confusion=test_confusion,
            subset_accuracy=subset_accuracy,
            subset_size=len(subset_predictions),
            dataset_summary=dataset_summary,
            elapsed=time.time() - started,
            checkpoint=args.out_dir / "garment_classifier.pt",
            labels_path=args.labels,
        )
        (args.out_dir / "report.md").write_text(report, encoding="utf-8", newline="\n")
        print(f"test accuracy {test_accuracy:.4f}  val accuracy {val_accuracy:.4f}")
        print(f"held-out subset ({len(subset_predictions)} images) torch accuracy {subset_accuracy:.4f}")
        print(f"train_classifier: wrote {args.out_dir}/report.md")
    except BootstrapError as exc:
        print(f"train_classifier: {exc}", file=sys.stderr)
        return 1
    return 0


def _quote(value: str) -> str:
    return f'"{value}"' if " " in value else value


def _render_report(
    *,
    args,
    command: str,
    labels: list[str],
    pairs: list[tuple[str, str]],
    vocab: dict[str, dict],
    history: list[dict],
    best_epoch: int,
    val_accuracy: float,
    test_accuracy: float,
    val_confusion: np.ndarray,
    test_confusion: np.ndarray,
    subset_accuracy: float,
    subset_size: int,
    dataset_summary: dict,
    elapsed: float,
    checkpoint: Path,
    labels_path: Path,
) -> str:
    counts = dataset_summary.get("splits", {})
    train_total = sum(counts.get("train", {}).values()) or "?"
    val_total = sum(counts.get("validation", {}).values()) or "?"
    test_total = sum(counts.get("test", {}).values()) or "?"
    commit = dataset_summary.get("commit", "unknown")
    epochs_table = "\n".join(
        f"| {row['epoch']} | {row['train_loss']:.4f} | {row['val_accuracy']:.4f} | "
        f"{row.get('seconds', 0):.0f} |"
        for row in history
    )
    mapping = "\n".join(
        f"| `{folder}` | {label} | {vocab[label]['category']} | {vocab[label]['name']} |"
        for folder, label in pairs
    )
    return f"""# Bootstrap classifier — measured report

**This is the BOOTSTRAP model, not the final one.** `docs/adr/0003` keeps the Kaggle
*Fashion Product Images* catalogue as the training set for the shipped classifier; that
dataset needs Kaggle credentials this machine does not have, so the pipeline is proven
with the CC0 set ADR-0003 already lists as optional augmentation:
`alexeygrigorev/clothing-dataset-small` (CC0-1.0, no attribution). Retrain on the
catalogue before treating any accuracy number here as the product's.

## Exact command

```
{command}
```

## Environment

| item | value |
| --- | --- |
| python | {platform.python_version()} ({sys.executable}) |
| platform | {platform.platform()} |
| torch | {torch.__version__} |
| torchvision | {torchvision.__version__} |
| device | {args.device} (CPU training; {torch.get_num_threads()} torch threads) |
| seed | {args.seed} |
| epochs | {args.epochs} (best epoch {best_epoch}), batch {args.batch_size}, AdamW lr {args.lr}, wd {args.weight_decay} |
| pretrained | ImageNet (`MobileNet_V3_Small_Weights.IMAGENET1K_V1`) |
| train wall clock | {elapsed / 60:.1f} min |
| dataset commit | {commit} ({DATASET_ID}) |
| labels.json sha256 | {sha256_file(labels_path)} |
| checkpoint sha256 | {sha256_file(checkpoint)} |

Data: {train_total} train / {val_total} validation / {test_total} test images, {len(labels)} classes.
Augmentation: RandomCrop(224) after Resize(256), horizontal flip, rotation ±10°, colour jitter
(0.2/0.2/0.2/0.02). Evaluation: Resize(256), CenterCrop(224), no augmentation.

## Class order (this IS the model's output order)

| folder | class | Category | Indonesian name |
| --- | --- | --- | --- |
{mapping}

Mapping notes: every class resolves through `ml_workspace/labels.json`. `Dress -> Tops` is
inherited from `labels.json` and is the one mapping with no clean Category — a dress is a
one-piece garment, and the five Categories from `CONTEXT.md` have no slot for it; Tops is
the least-bad (the model never predicts the Category directly, the app maps the label).
`Hat -> Accessories` is the only Accessories class, and this dataset has no other
Accessories garment at all, so this model discriminates `Shoes`/`Accessories` poorly by
construction. `outwear` (the dataset's spelling of outerwear) maps to `Outwear -> Outerwear`.

## Accuracy (measured, PyTorch float32)

| split | top-1 accuracy | images |
| --- | --- | --- |
| validation | {val_accuracy:.4f} | {val_total} |
| test | {test_accuracy:.4f} | {test_total} |

### Per-class accuracy — test

{markdown_per_class(test_confusion, labels)}

### Per-class accuracy — validation

{markdown_per_class(val_confusion, labels)}

## Confusion matrix — test (rows true, columns predicted)

{markdown_confusion(test_confusion, labels)}

## Confusion matrix — validation (rows true, columns predicted)

{markdown_confusion(val_confusion, labels)}

## Training curve

| epoch | train loss | val accuracy | seconds |
| --- | --- | --- | --- |
{epochs_table}

## Conversion fidelity (filled in by `export_tflite.py`)

The PyTorch reference on the shared held-out subset is **{subset_accuracy:.4f}** over
{subset_size} test images ({args.subset_per_class} per class, seed {args.seed}, the same
files `artifacts/subset_predictions.json` records). `export_tflite.py` appends the
converted `.tflite`'s accuracy on that identical list below; a converted model that scores
near chance means the conversion is broken and must not ship.

<!-- export-tflite-section -->
"""


if __name__ == "__main__":
    raise SystemExit(main())
