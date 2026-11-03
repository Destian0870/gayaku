# Bootstrap classifier — CC0 data, so the scanner pipeline runs today

**This is a BOOTSTRAP model, not the final one.** `docs/adr/0003` keeps the Kaggle
*Fashion Product Images* catalogue as the training set of the shipped classifier. That
catalogue needs Kaggle credentials (`~/.kaggle/kaggle.json` or `KAGGLE_USERNAME`/`KAGGLE_KEY`)
and none exist on this machine, so the app's classifier half had no `.tflite` at all and
`scan_pipeline.dart` could not run. This folder trains a real classifier on
`alexeygrigorev/clothing-dataset-small` — the CC0 (no attribution) set ADR-0003 itself lists
as optional augmentation, so it is a legitimate bootstrap source, not a replacement decision.
Retrain on the catalogue before treating any accuracy here as the product's.

What it produced:

| artifact | what it is |
| --- | --- |
| `flutter_app/assets/models/garment_classifier.tflite` | the shipped model, 6,129,368 bytes, sha256 `4dea19d6b3dbe30bd5a8dc9686803afdd657e9dedbf234d0fd61e5a6be313457` |
| `flutter_app/lib/logic/garment_labels.dart` | regenerated: 10 classes, matching the model's `[1,10]` output width |
| `artifacts/report.md` | measured metrics: per-class accuracy, both confusion matrices, conversion fidelity |
| `artifacts/classes.json` | the trained class order — index = model output index |

## The numbers (measured, not estimated)

| metric | value |
| --- | --- |
| validation top-1 (341 images) | 0.9091 |
| test top-1 (372 images) | 0.9194 |
| PyTorch top-1 on the shared held-out subset (179 test images) | 0.9385 |
| converted `.tflite` top-1 on that same 179-image list | 0.9385 |
| per-image top-1 agreement, `.tflite` vs PyTorch | 1.0000 |
| ONNX vs PyTorch max abs diff (onnxruntime) | 2.68e-07 |
| model IO | input `image` `[1,224,224,3]` float32 NHWC, output `[1,10]` float32 softmax |

Full tables (per-class accuracy, both confusion matrices, training curve, per-class
conversion agreement) live in `artifacts/report.md`.

## Reproduce

Run from the repository root. Steps 1–3 use the Anaconda interpreter (torch), step 4 uses the
conversion venv (TensorFlow), step 5 is plain Python, step 6 is Flutter.

```bash
# 0. environment, Windows Python 3.14.6 (Anaconda) — already installed here
python -m pip install torch torchvision onnx onnxruntime

# 0b. conversion venv (only step 4 needs it); see "Which environment each step ran in"
python -m venv ml_workspace/bootstrap/.venv-convert
ml_workspace/bootstrap/.venv-convert/Scripts/python.exe -m pip install \
  tensorflow onnx2tf pillow numpy onnx onnxruntime tf_keras-nightly psutil

# 1. dataset: CC0, ~103 MB, shallow clone into bootstrap/data/ (git-ignored)
python ml_workspace/bootstrap/fetch_dataset.py

# 2. train (CPU, ~18 min for 8 epochs on 16 threads; writes artifacts/{classes.json,report.md,garment_classifier.pt})
python ml_workspace/bootstrap/train_classifier.py --epochs 8

# 3. ONNX audit copy: NCHW [1,3,224,224], normalisation as the first ops, softmax last
python ml_workspace/bootstrap/export_tflite.py onnx

# 4. ONNX -> TFLite (NHWC), then verify: tensor IO + 179-image accuracy vs PyTorch, then ship
ml_workspace/bootstrap/.venv-convert/Scripts/python.exe ml_workspace/bootstrap/export_tflite.py tflite

# 5. regenerate the Dart class list from the exported model's class list (never hand-edit it)
python ml_workspace/scripts/gen_dart_labels.py \
  --classes ml_workspace/bootstrap/artifacts/classes.json \
  --labels ml_workspace/labels.json \
  --out flutter_app/lib/logic/garment_labels.dart

# 6. the app side
cd flutter_app && flutter analyze && flutter test
```

Step 4 ships the model only if the converted model scores >= 0.50 and within 0.10 absolute of
PyTorch on the held-out subset; a broken conversion therefore cannot reach the app. Step 5
must be re-run whenever `classes.json` changes: `scan_pipeline.dart` compares the model's
output width with `garmentCategories.length` and throws a user-visible Indonesian error
otherwise. Re-running steps 1–3 rewrites `report.md`, so re-run step 4 after them (it is what
adds the conversion section).

### Which environment each step ran in

| step | environment |
| --- | --- |
| 0–3, 5 | Windows 11, Anaconda Python 3.14.6, torch 2.14.1+cpu, torchvision 0.29.1+cpu, onnx 1.23.2, onnxruntime 1.31.0 |
| 4 | `ml_workspace/bootstrap/.venv-convert` (Python 3.14.6), tensorflow 2.22.0rc0, onnx2tf 1.28.8, onnx 1.23.2 |
| 6 | Flutter 3.47.2, Windows |

WSL was **not** used: the conversion works on Windows. Two things make that work, and both are
recorded here because they are easy to trip over:

* `onnx2tf` imports `tf_keras`, and no `keras`-2 package imports against TensorFlow 2.22.0rc0
  (`tf.__internal__.register_load_context_function` is gone). This venv therefore has
  `tf_keras-nightly` — the only build matching that TensorFlow — plus `psutil`, which
  `onnx2tf` imports but does not declare:
  `python -m pip install tensorflow onnx2tf pillow numpy onnx onnxruntime tf_keras-nightly psutil`.
  If a stable TensorFlow is available for the interpreter in use (any Ubuntu/macOS Python, or
  Windows Python ≤ 3.13), the plain `pip install tensorflow onnx2tf` list is enough.
* `onnx2tf` 1.28.8 downloads `calibration_image_sample_data_20x128x128x3_float32.npy` from a
  pinned release URL that now returns 404, and only fails over on a *timeout*, so `np.load`
  chokes on the error page. `export_tflite.py` writes that file into the converter's scratch
  directory itself (20 held-out photographs resized to 128×128, `[0,1]` float32), which is
  the shape and range onnx2tf expects. Those samples only feed a throwaway dummy run — the
  real verification is the 179-image accuracy comparison against PyTorch.
* The ONNX copy is exported with `dynamo=False` (the legacy TorchScript exporter, opset 17):
  torch 2.14 defaults to the new exporter, which needs `onnxscript`, and opset-17 legacy is
  the combination `onnx2tf` handles best. torch prints a deprecation warning for it.

For whoever owns it: `docs/adr/0001-scanner-inference-on-device.md` still says LiteRT export
"runs on Linux/macOS only, so exports happen in WSL or Colab". This run contradicts that — the
ONNX→TFLite step ran on Windows 11 with TensorFlow 2.22.0rc0 — but ADRs are not this run's to
edit.

### Commands that diagnose a model without training it

```bash
python ml_workspace/bootstrap/fetch_dataset.py --force          # re-clone the dataset
python ml_workspace/bootstrap/export_tflite.py tflite --no-ship # verify without touching the app assets
python ml_workspace/scripts/tflite_io.py flutter_app/assets/models/garment_classifier.tflite
```

## Data

`alexeygrigorev/clothing-dataset-small` — CC0-1.0, ImageFolder layout, commit
`11961516512414bf9f6c150a832cfd21b54a6b54`: 3068 train / 341 validation / 372 test images over
10 folders. `fetch_dataset.py` clones it into `bootstrap/data/` (`bootstrap/.gitignore` keeps
it, and every run output except `classes.json`/`report.md`, out of git). It fails clearly with
no network: `git ls-remote` is the reachability probe, a failed clone is removed instead of
left half-written, and a non-empty non-clone destination is refused unless `--force`.

Training: MobileNetV3-small at 224 px, ImageNet weights, head replaced for the 10 classes;
augmentation is Resize(256) + RandomCrop(224), horizontal flip, rotation ±10°, colour jitter
0.2/0.2/0.2/0.02; AdamW lr 1e-3, weight decay 1e-4, cosine schedule, batch 32, seed 42, CPU.
The exported ONNX/TFLite graph wraps the network so ImageNet normalisation is the first op,
and ends in a softmax because `scan_pipeline.dart` reads the winning score as its confidence.
Validation accuracy was still improving at epoch 8; more epochs are cheap if anyone wants them.

## Class mapping, and the one thing to fix

Class order comes from `labels.json`'s CC0 entries (`keep: true`), restricted to the folders the
clone actually has — the same rule `prepare_data.py` uses for the catalogue. All 10 folders
resolve, no `labels.json` change was needed:

| folder | class | Category | Indonesian name |
| --- | --- | --- | --- |
| `t-shirt` | T-Shirt | Tops | Kaos |
| `shirt` | Shirt | Tops | Kemeja |
| `longsleeve` | Longsleeve | Tops | Kaos Lengan Panjang |
| `outwear` | Outwear | Outerwear | Jaket |
| `dress` | Dress | Tops | Gaun |
| `skirt` | Skirt | Bottoms | Rok |
| `pants` | Pants | Bottoms | Celana Panjang |
| `shorts` | Shorts | Bottoms | Celana Pendek |
| `shoes` | Shoes | Shoes | Sepatu |
| `hat` | Hat | Accessories | Topi |

* **`Dress -> Tops` has no good Category** and it is inherited from `ml_workspace/labels.json`,
  which this run is not allowed to change. A dress is a one-piece garment; the five Categories
  from `CONTEXT.md` have no slot for it, and Tops is simply the least-bad of them. The next
  person to touch classification should decide this properly — either a `Dresses`/`Kebaya`
  style Category or an explicit "one-piece" rule. `sweater`/`hoodie`-shaped labels from the
  full CC0 set hit the same question later.
* `Hat` is the only Accessories class and the only non-wearable-on-a-stage-of-dressing class
  here, so this model's Accessories output is a hat detector and nothing more; the CC0 set has
  no bags, belts or sunglasses at all. The catalogue path (ADR-0003) is what fixes that.
* `outwear` is the dataset's own spelling; the label keeps it (`Outwear`, "Jaket") and maps to
  the `Outerwear` Category.

## The codegen rule

`garmentCategories[i]` in `flutter_app/lib/logic/garment_labels.dart` must name the class that
the exported model's `scores[i]` means, so the Dart list is generated from the class list of
whichever model was exported — here `ml_workspace/bootstrap/artifacts/classes.json`. Never
hand-edit the Dart file, and never regenerate it from `ml_workspace/artifacts/classes.json`
(the 80-class catalogue list) while the shipped model is this 10-class bootstrap: the app
refuses to run on a mismatch rather than mislabelling every garment by one index. If a class
has no entry in `labels.json`, the generator exits non-zero instead of shipping a nameless
class.

## Licence

Dataset CC0-1.0 (no attribution). The model is trained from it, so it carries no third-party
weights beyond the Apache-2.0 torchvision ImageNet initialisation. This is coursework like
`docs/adr/0003`'s catalogue weights: not redistributed, not shipped commercially.
