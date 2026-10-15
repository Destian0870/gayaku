#!/usr/bin/env python3
"""Export the bootstrap classifier to ONNX (NCHW) and then to TFLite (NHWC).

Two steps, two interpreters, because they need different packages:

    # step 1 — training environment (torch + onnx + onnxruntime)
    python ml_workspace/bootstrap/export_tflite.py onnx

    # step 2 — conversion environment (tensorflow + onnx2tf + pillow)
    python ml_workspace/bootstrap/export_tflite.py tflite

Step 1 wraps the checkpoint in the same `[0,1]`-in model the training script used, so
the ONNX graph's first ops normalise the input, and the ONNX input is NCHW
`[1,3,224,224]`. Step 2 runs `onnx2tf`, which turns that into NHWC `[1,224,224,3]` as
`flutter_app/lib/logic/scan_pipeline.dart` expects, then

* checks the exported tensors with `ml_workspace/scripts/tflite_io.py`,
* runs the `.tflite` over the same held-out test subset the PyTorch run scored
  (`artifacts/subset_predictions.json`) and records its top-1 accuracy next to the
  PyTorch number in `artifacts/report.md` — a converted model near chance means the
  conversion is broken,
* refuses to ship (and says why) if the converted model loses more than 0.10 absolute
  accuracy against PyTorch or scores below 0.50,
* otherwise copies the verified file to `flutter_app/assets/models/garment_classifier.tflite`.

If TensorFlow has no wheel for the Windows interpreter, run step 2 in WSL with
`bootstrap/export_tflite_wsl.sh`, which builds the conversion venv and calls the same
`tflite` subcommand.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from common import (
    DEFAULT_ARTIFACTS,
    DEFAULT_DATA_DIR,
    REPO_ROOT,
    BootstrapError,
    dataset_classes,
    eval_transform,
    held_out_subset,
    read_json,
    sha256_file,
    vocabulary,
    write_json,
)

SHIPPED_MODEL = REPO_ROOT / "flutter_app" / "assets" / "models" / "garment_classifier.tflite"
TFLITE_IO = REPO_ROOT / "ml_workspace" / "scripts" / "tflite_io.py"
INPUT_SIZE = 224
INPUT_NAME = "image"
OUTPUT_NAME = "scores"
PLACEHOLDER_MARKER = "<!-- export-tflite-section -->"
SECTION_MARKER = "## Converted model (.tflite) fidelity check"
SAMPLE_FILE = "calibration_image_sample_data_20x128x128x3_float32.npy"
SAMPLE_COUNT = 20
SAMPLE_SIZE = 128


# --------------------------------------------------------------------------- ONNX


def build_export_model(checkpoint: dict, num_classes: int):
    """The checkpoint's module (raw `[0,1]` pixels in) wrapped in a softmax.

    Training needs logits (`CrossEntropyLoss`), the app needs probabilities
    (`scan_pipeline.dart` uses the winning score directly as `confidence`), so the
    softmax is added here — as the last op of the exported graph — rather than
    baked into the training module.
    """
    import torch

    from train_classifier import NormalizedClassifier

    inner = NormalizedClassifier(num_classes, pretrained=False)
    inner.load_state_dict(checkpoint["model"])

    class ExportedSoftmax(torch.nn.Module):
        def __init__(self, inner: torch.nn.Module) -> None:
            super().__init__()
            self.inner = inner

        def forward(self, x):
            return torch.softmax(self.inner(x), dim=1)

    return ExportedSoftmax(inner).eval()


def export_onnx(args) -> int:
    import onnx
    import onnxruntime as ort
    import torch

    checkpoint_path = args.artifacts / "garment_classifier.pt"
    if not checkpoint_path.is_file():
        raise BootstrapError(f"{checkpoint_path} is missing — run train_classifier.py first")
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=True)
    labels: list[str] = checkpoint["labels"]
    model = build_export_model(checkpoint, len(labels))

    onnx_path = args.artifacts / "garment_classifier.onnx"
    dummy = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
    with torch.no_grad():
        torch.onnx.export(
            model,
            (dummy,),
            str(onnx_path),
            input_names=[INPUT_NAME],
            output_names=[OUTPUT_NAME],
            opset_version=args.opset,
            do_constant_folding=True,
            dynamo=args.dynamo,
        )
    onnx.checker.check_model(str(onnx_path))

    graph = onnx.load(str(onnx_path)).graph
    inputs = [
        (value.name, [dim.dim_value for dim in value.type.tensor_type.shape.dim])
        for value in graph.input
    ]
    outputs = [
        (value.name, [dim.dim_value for dim in value.type.tensor_type.shape.dim])
        for value in graph.output
    ]
    if inputs != [(INPUT_NAME, [1, 3, INPUT_SIZE, INPUT_SIZE])]:
        raise BootstrapError(f"unexpected ONNX input {inputs}")
    if outputs != [(OUTPUT_NAME, [1, len(labels)])]:
        raise BootstrapError(f"unexpected ONNX output {outputs}")

    first_ops = ", ".join(f"{node.op_type}({node.name or '-'})" for node in graph.node[:3])

    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    generator = np.random.default_rng(0)
    max_diff = 0.0
    softmax_error = 0.0
    for _ in range(4):
        probe = generator.random((1, 3, INPUT_SIZE, INPUT_SIZE), dtype=np.float32)
        with torch.no_grad():
            expected = model(torch.from_numpy(probe)).numpy()
        actual = session.run([OUTPUT_NAME], {INPUT_NAME: probe})[0]
        max_diff = max(max_diff, float(np.abs(expected - actual).max()))
        softmax_error = max(softmax_error, float(abs(actual.sum() - 1.0)))

    write_json(
        args.artifacts / "onnx_io.json",
        {
            "path": str(onnx_path),
            "sha256": sha256_file(onnx_path),
            "bytes": onnx_path.stat().st_size,
            "opset": args.opset,
            "exporter": "torch.onnx.export (dynamo=%s)" % args.dynamo,
            "inputs": inputs,
            "outputs": outputs,
            "first_ops": first_ops,
            "onnxruntime_max_abs_diff_vs_torch": max_diff,
            "onnxruntime_max_softmax_sum_error": softmax_error,
            "torch": torch.__version__,
            "onnx": onnx.__version__,
            "onnxruntime": ort.__version__,
        },
    )
    print(f"export_tflite(onnx): wrote {onnx_path} ({onnx_path.stat().st_size} bytes)")
    print(f"  input  {inputs[0][0]} {inputs[0][1]} float32   (NCHW, [0,1] pixels)")
    print(f"  output {outputs[0][0]} {outputs[0][1]} float32   (softmax)")
    print(f"  first ops: {first_ops}")
    print(f"  onnxruntime vs torch max abs diff: {max_diff:.3e}")
    if max_diff > 1e-4:
        raise BootstrapError(f"ONNX graph disagrees with PyTorch (max diff {max_diff:.3e})")
    return 0


# ------------------------------------------------------------------------- TFLite


def convert_onnx_to_tflite(onnx_path: Path, out_dir: Path, keep_tflite: Path, sample_images):
    import onnx2tf
    import os

    with tempfile.TemporaryDirectory() as scratch_name:
        scratch = Path(scratch_name)
        write_sample_data(scratch, sample_images)
        previous = os.getcwd()
        try:
            os.chdir(scratch)  # onnx2tf looks for its sample data in the cwd
            onnx2tf.convert(
                input_onnx_file_path=str(onnx_path.resolve()),
                output_folder_path=str((scratch / "out").resolve()),
                batch_size=1,
                non_verbose=True,
            )
        finally:
            os.chdir(previous)
        produced = sorted((scratch / "out").glob("*_float32.tflite")) or sorted(
            (scratch / "out").glob("*.tflite")
        )
        if not produced:
            raise BootstrapError(f"onnx2tf produced no .tflite in {scratch / 'out'}")
        out_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(produced[0], keep_tflite)
    return keep_tflite


def write_sample_data(scratch: Path, sample_images) -> Path:
    """Hand onnx2tf the `calibration_image_sample_data_20x128x128x3_float32.npy` it downloads.

    onnx2tf 1.28.8 fetches that file from
    `github.com/PINTO0309/onnx2tf/releases/download/1.20.4/...` and falls back to Wasabi
    only on a *timeout*, so today's 404 makes `np.load` choke on the error page and the
    conversion dies before touching the graph. The file is only dummy input for a
    throwaway ONNX run (`check_onnx_tf_outputs_elementwise_close` is off, and this script
    replaces that check with a real 179-image accuracy comparison), so we write it from
    held-out photographs of our own dataset in exactly the expected shape and range.
    """
    import numpy as np

    data = np.zeros((SAMPLE_COUNT, SAMPLE_SIZE, SAMPLE_SIZE, 3), dtype=np.float32)
    for index, path in enumerate(sample_images[:SAMPLE_COUNT]):
        with Image.open(path) as image:
            resized = image.convert("RGB").resize((SAMPLE_SIZE, SAMPLE_SIZE), Image.BILINEAR)
        data[index] = np.asarray(resized, dtype=np.float32) / 255.0
    path = scratch / SAMPLE_FILE
    np.save(path, data)
    return path


def load_labels(artifacts: Path) -> list[str]:
    classes = read_json(artifacts / "classes.json")
    labels = classes["labels"]
    if not labels:
        raise BootstrapError(f"{artifacts / 'classes.json'} lists no classes")
    return labels


def held_out_items(args, labels: list[str]):
    """The shared held-out list, rebuilt from the dataset so the paths work here too.

    `subset_predictions.json` records absolute Windows paths for the evidence trail;
    this script rebuilds the same list from `--data-dir` (which is what lets the
    conversion step run in WSL on a `/mnt/...` path) and checks the file names agree.
    """
    reference = read_json(args.artifacts / "subset_predictions.json")
    vocab = vocabulary(args.labels)
    pairs = dataset_classes(args.data_dir, vocab)
    folders = [folder for folder, _ in pairs]
    folder_index = {folder: position for position, folder in enumerate(folders)}
    for folder, label in pairs:
        if labels[folder_index[folder]] != label:
            raise BootstrapError(
                f"classes.json order disagrees with labels.json at {folder!r} -> {label!r}"
            )
    subset = held_out_subset(
        args.data_dir, "test", folders, reference["per_class"], reference["seed"]
    )
    recorded = [Path(row["image"]).name for row in reference["predictions"]]
    if [path.name for path, _ in subset] != recorded:
        raise BootstrapError(
            "the held-out subset differs from the one recorded in subset_predictions.json; "
            "re-run train_classifier.py before the conversion check"
        )
    return reference, subset, folders, folder_index


def compute_fidelity(args, labels: list[str], tflite_path: Path, reference, subset, folders, folder_index):
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    input_shape = [int(value) for value in input_detail["shape"]]
    output_shape = [int(value) for value in output_detail["shape"]]
    if input_shape != [1, INPUT_SIZE, INPUT_SIZE, 3]:
        raise BootstrapError(f"converted input is {input_shape}, not [1,224,224,3] NHWC")
    if output_shape != [1, len(labels)]:
        raise BootstrapError(f"converted output is {output_shape}, not [1,{len(labels)}]")

    rows = []
    for (path, folder), record in zip(subset, reference["predictions"]):
        with Image.open(path) as image:
            pixels = eval_transform(image, INPUT_SIZE)[None, ...]
        interpreter.set_tensor(input_detail["index"], pixels.astype(np.float32))
        interpreter.invoke()
        probabilities = interpreter.get_tensor(output_detail["index"])[0]
        index = int(np.argmax(probabilities))
        rows.append(
            {
                "image": path.as_posix(),
                "true": folder,
                "pred": folders[index],
                "pred_index": index,
                "true_index": folder_index[folder],
                "confidence": float(probabilities[index]),
                "sum": float(probabilities.sum()),
                "torch_index": record["pred_index"],
                "torch_confidence": record["confidence"],
            }
        )

    total = len(rows)
    accuracy = sum(1 for row in rows if row["pred_index"] == row["true_index"]) / total
    agreement = sum(1 for row in rows if row["pred_index"] == row["torch_index"]) / total
    max_prob_diff = float(
        max(abs(row["confidence"] - row["torch_confidence"]) for row in rows)
    )
    max_sum_error = float(max(abs(row["sum"] - 1.0) for row in rows))
    return rows, accuracy, agreement, max_prob_diff, max_sum_error


def tflite_io_text(model: Path) -> str:
    result = subprocess.run(
        [sys.executable, str(TFLITE_IO), str(model)],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def append_report_section(report: Path, section: str) -> None:
    """Replace everything from the marker on: the section is reproducible, not appended twice."""
    text = report.read_text(encoding="utf-8")
    marker_index = text.find(PLACEHOLDER_MARKER)
    head = text[:marker_index].rstrip() if marker_index != -1 else text.rstrip()
    report.write_text(
        head + "\n\n" + PLACEHOLDER_MARKER + "\n\n" + section.strip() + "\n",
        encoding="utf-8",
        newline="\n",
    )


def export_tflite(args) -> int:
    import onnx
    import tensorflow as tf

    labels = load_labels(args.artifacts)
    onnx_path = args.artifacts / "garment_classifier.onnx"
    if not onnx_path.is_file():
        raise BootstrapError(f"{onnx_path} is missing — run `export_tflite.py onnx` first")
    reference, subset, folders, folder_index = held_out_items(args, labels)
    tflite_path = args.artifacts / "garment_classifier.tflite"
    convert_onnx_to_tflite(
        onnx_path,
        args.artifacts,
        tflite_path,
        [path for path, _ in subset[:SAMPLE_COUNT]],
    )

    io_text = tflite_io_text(tflite_path)
    rows, accuracy, agreement, max_prob_diff, max_sum_error = compute_fidelity(
        args, labels, tflite_path, reference, subset, folders, folder_index
    )
    torch_accuracy = float(reference["torch_accuracy"])
    py_class_accuracies = {}
    for row in reference["predictions"]:
        bucket = py_class_accuracies.setdefault(row["true"], [0, 0])
        bucket[1] += 1
        bucket[0] += int(row["pred_index"] == row["true_index"])
    tflite_class_accuracies = {}
    for row in rows:
        bucket = tflite_class_accuracies.setdefault(row["true"], [0, 0])
        bucket[1] += 1
        bucket[0] += int(row["pred_index"] == row["true_index"])

    order = sorted(tflite_class_accuracies)
    per_class = "\n".join(
        f"| {folder} | {tflite_class_accuracies[folder][1]} | "
        f"{py_class_accuracies[folder][0] / py_class_accuracies[folder][1]:.3f} | "
        f"{tflite_class_accuracies[folder][0] / tflite_class_accuracies[folder][1]:.3f} | "
        f"{sum(1 for row in rows if row['true'] == folder and row['pred_index'] == row['torch_index']) / tflite_class_accuracies[folder][1]:.3f} |"
        for folder in order
    )

    gate_ok = accuracy >= 0.50 and accuracy >= torch_accuracy - 0.10
    shipped = None
    if gate_ok and not args.no_ship:
        SHIPPED_MODEL.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(tflite_path, SHIPPED_MODEL)
        shipped = SHIPPED_MODEL
    onnx_io = read_json(args.artifacts / "onnx_io.json")
    shipped_note = (
        f"`flutter_app/assets/models/garment_classifier.tflite` ({sha256_file(shipped)})"
        if shipped
        else ("skipped (--no-ship)" if gate_ok else "none — the gate failed, nothing shipped")
    )
    import onnx2tf

    section = f"""{SECTION_MARKER}

Two steps: the ONNX audit copy (torch) and the LiteRT export (TensorFlow + onnx2tf).

### Step 1 — ONNX audit copy

```
{onnx_io['exporter']}, opset {onnx_io['opset']}, {onnx_io['bytes']} bytes, sha256 {onnx_io['sha256']}
input  {onnx_io['inputs'][0][0]} {onnx_io['inputs'][0][1]}   (NCHW — transposed to NHWC by the converter)
output {onnx_io['outputs'][0][0]} {onnx_io['outputs'][0][1]}
first ops: {onnx_io['first_ops']}
onnxruntime vs torch: max abs diff {onnx_io['onnxruntime_max_abs_diff_vs_torch']:.3e},
  max |sum(probabilities) - 1| {onnx_io['onnxruntime_max_softmax_sum_error']:.3e}
```

The first two ops are the normalisation (`Sub`, `Div`), i.e. callers feed raw `[0,1]` pixels,
and the graph ends in a softmax — the app uses the winning score as its `confidence`
(`scan_pipeline.dart`), so logits would be wrong.

### Step 2 — conversion

```
{args.command_line}
```

Environment: {sys.executable}, python {sys.version.split()[0]}, tensorflow {tf.__version__},
onnx {onnx.__version__}, onnx2tf {onnx2tf.__version__} (`convert(..., batch_size=1)`), converter
sample data supplied locally (see README).

### Tensor IO, read from the exported flatbuffer

```
{io_text}
```

### Measured top-1 accuracy on the shared held-out subset

| model | accuracy | images |
| --- | --- | --- |
| PyTorch float32 (reference) | {torch_accuracy:.4f} | {len(reference['predictions'])} |
| converted `.tflite` | {accuracy:.4f} | {len(rows)} |

Same {len(rows)} files, same list order, same preprocessing — `artifacts/subset_predictions.json`
records the PyTorch side, `artifacts/tflite_predictions.json` the converted side.

* per-image top-1 agreement with PyTorch: {agreement:.4f}
* largest softmax probability deviation from PyTorch: {max_prob_diff:.4f}
* largest `sum(probabilities) - 1` error (softmax really is the last op): {max_sum_error:.3e}
* gate: accuracy >= 0.50 and >= PyTorch - 0.10 → {"PASSED" if gate_ok else "FAILED"}
* shipped copy: {shipped_note}

| class (test subset) | images | PyTorch accuracy | .tflite accuracy | top-1 agreement |
| --- | --- | --- | --- | --- |
{per_class}

Model file: {tflite_path.stat().st_size} bytes, sha256 {sha256_file(tflite_path)}.
The Dart class list is generated from `bootstrap/artifacts/classes.json` (see README's codegen
rule), so its length must equal {len(labels)} — `scan_pipeline.dart` refuses to run otherwise.
"""
    if args.report.is_file():
        append_report_section(args.report, section)
    write_json(
        args.artifacts / "tflite_io.json",
        {"text": io_text, "sha256": sha256_file(tflite_path), "bytes": tflite_path.stat().st_size},
    )
    write_json(
        args.artifacts / "tflite_predictions.json",
        {
            "subset": "test",
            "per_class": reference["per_class"],
            "seed": reference["seed"],
            "accuracy": accuracy,
            "torch_accuracy": torch_accuracy,
            "agreement": agreement,
            "max_probability_difference": max_prob_diff,
            "max_softmax_sum_error": max_sum_error,
            "gate_passed": gate_ok,
            "predictions": rows,
        },
    )
    print(f"export_tflite(tflite): wrote {tflite_path} ({tflite_path.stat().st_size} bytes)")
    print("  " + next(line.strip() for line in io_text.splitlines() if "input 0" in line))
    print(f"  tflite accuracy {accuracy:.4f} vs torch {torch_accuracy:.4f} on {len(rows)} images")
    print(f"  top-1 agreement {agreement:.4f}, max prob diff {max_prob_diff:.4f}")
    if not gate_ok:
        raise BootstrapError(
            f"converted model scored {accuracy:.4f} against PyTorch's {torch_accuracy:.4f}: "
            "the conversion is broken, not shipped"
        )
    if shipped:
        print(f"  shipped {shipped} ({sha256_file(shipped)})")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("step", choices=("onnx", "tflite"))
    parser.add_argument("--artifacts", type=Path, default=DEFAULT_ARTIFACTS, help="%(default)s")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR, help="%(default)s")
    parser.add_argument("--labels", type=Path, default=REPO_ROOT / "ml_workspace" / "labels.json")
    parser.add_argument("--report", type=Path, default=None, help="default: <artifacts>/report.md")
    parser.add_argument("--opset", type=int, default=17)
    parser.add_argument("--dynamo", action="store_true", help="use the new dynamo ONNX exporter")
    parser.add_argument("--no-ship", action="store_true", help="do not copy into the app assets")
    args = parser.parse_args(argv)
    # Absolute up front: the conversion step chdir()s into its own scratch directory.
    args.artifacts = args.artifacts.resolve()
    args.data_dir = args.data_dir.resolve()
    args.labels = args.labels.resolve()
    if args.report is None:
        args.report = args.artifacts / "report.md"
    args.command_line = f'"{sys.executable}" ml_workspace/bootstrap/export_tflite.py ' + " ".join(
        (argv if argv is not None else sys.argv[1:])
    )

    try:
        return export_onnx(args) if args.step == "onnx" else export_tflite(args)
    except BootstrapError as exc:
        print(f"export_tflite: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
