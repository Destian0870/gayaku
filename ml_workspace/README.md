# ml_workspace — the offline model lab

Offline work only: dataset gathering, training, evaluation, export. The app ships the
resulting `.tflite` files and runs them on device; nothing here runs at runtime
(`docs/adr/0001-scanner-inference-on-device.md`). Decisions that bound this folder:
`0002` (permissive model licences only), `0003` (the Kaggle catalogue is the training data),
`0005` (matte the photo, then classify the cutout, one garment per photo).

## Layout

| Path | Committed? | What it is |
|---|---|---|
| `labels.json` | yes | semantic source of truth: one entry per catalogue `articleType` (143 of them) plus the CC0 bootstrap vocabulary, each with `category`, Indonesian `name`, `keep` and the `dataset` it belongs to |
| `artifacts/classes.json` | yes | the classifier's class list. **`labels[i]` is the label score `i` means** — this file *is* the model's output order |
| `scripts/prepare_data.py` | yes | Kaggle download, label cleanup, stratified 80/10/10 split, writes `artifacts/classes.json` |
| `scripts/gen_dart_labels.py` | yes | emits `flutter_app/lib/logic/garment_labels.dart` from `classes.json` + `labels.json` |
| `scripts/fetch_matting_model.py` | yes | fetches + verifies `flutter_app/assets/models/u2netp_320.tflite` |
| `scripts/tflite_io.py` | yes | reads a `.tflite`'s tensor IO with no TensorFlow/LiteRT install (tiny flatbuffers reader) |
| `kaggle/fashion_classifier.ipynb` | yes | the training venue: MobileNetV3-small, evaluation, ONNX + TFLite export |
| `data/` | no | downloaded catalogue, `train.csv`/`val.csv`/`test.csv`, `data/split_summary.json` |
| `artifacts/garment_classifier.*`, `artifacts/report.md` | produced | exported model, ONNX audit copy, metrics report |

## Contracts

**Classifier** — input `image` `[1,224,224,3]` float32 NHWC RGB in `[0,1]`; ImageNet
normalisation is baked into the exported graph by a wrapper module, so callers feed raw
`[0,1]` pixels. Output `scores` `[1,N]` float32 softmax, class order = `garmentCategories`
in the generated Dart file = `labels` in `artifacts/classes.json`.

**Matting** (`u2netp_320.tflite`, in `flutter_app/assets/models/`) — input
`serving_default_input.1:0` `[1,320,320,3]` float32 NHWC RGB in `[0,1]`; seven outputs, all
`[1,320,320,1]` float32, of which output 0 (`PartitionedCall:1`) is the saliency mask in
`[0,1]`. Read from the flatbuffer with `scripts/tflite_io.py`, cross-checked against the
pip `tflite` schema bindings; sha256
`558136589a47e97f53944ac3f65ba56f4efb5f6bae8e92b573e7c463d20fdb58`, 4,575,464 bytes,
Apache-2.0 (see `flutter_app/assets/models/LICENSES.md`). Note this is **NHWC**, not the
NCHW `[1,3,320,320]` of the LiteRT-community *full* U²-Net build: that one is 88 MB, so
`docs/adr/0005`'s APK budget (u2netp, 5–9 MB) wins and the Dart side packs NHWC.

## The codegen rule

`garmentCategories[i]` must name the class that the exported model's `scores[i]` means.
Never hand-edit `flutter_app/lib/logic/garment_labels.dart`: regenerate it from the class
list, and if a class has no entry in `labels.json` the generator **exits non-zero** instead
of shipping a nameless class. So a new class always arrives with a Category and an
Indonesian name, or not at all.

## Commands

Run everything from the repository root.

```bash
# 1. matting model (over HTTPS, verifies TFL3 + prints sha256 and tensor IO)
python ml_workspace/scripts/fetch_matting_model.py

# 2. class list without touching the network (~ the committed artifacts/classes.json)
python ml_workspace/scripts/prepare_data.py --labels-only

# 3. full prep: download the catalogue, clean labels, split 80/10/10 by articleType
#    needs ~/.kaggle/kaggle.json or KAGGLE_USERNAME + KAGGLE_KEY, plus `pip install kaggle`
python ml_workspace/scripts/prepare_data.py
python ml_workspace/scripts/prepare_data.py --dataset paramaggarwal/fashion-product-images-small
python ml_workspace/scripts/prepare_data.py --catalogue-dir /kaggle/input/fashion-product-images-small

# 3b. class list for the local CC0 bootstrap run (alexeygrigorev/clothing-dataset)
python ml_workspace/scripts/prepare_data.py --labels-only --dataset alexeygrigorev/clothing-dataset

# 4. train + export on Kaggle (GPU + Internet, inputs: the catalogue and this labels.json)
#    upload ml_workspace/kaggle/fashion_classifier.ipynb, run all; it writes
#    artifacts/{garment_classifier.tflite,garment_classifier.onnx,classes.json,report.md}

# 5. regenerate the Dart label file after every export (idempotent; --check for CI/pre-commit)
python ml_workspace/scripts/gen_dart_labels.py
python ml_workspace/scripts/gen_dart_labels.py --check

# 6. read any exported model's IO contract before wiring it up
python ml_workspace/scripts/tflite_io.py flutter_app/assets/models/garment_classifier.tflite
python ml_workspace/scripts/tflite_io.py flutter_app/assets/models/u2netp_320.tflite --json
```

`prepare_data.py` fails loudly rather than silently degrading: without a Kaggle token it
prints where a token is expected (and that `--labels-only`/`--catalogue-dir` need none),
and it stops if a `keep: true` label has fewer than 8 photographs, because such a class
cannot be stratified honestly.

## `labels.json` semantics

* `keep: true` — a class we train on: a single wearable item with at least 8 photographs in
  the catalogue snapshot (44,424 rows, 143 distinct `articleType` values → 80 classes).
* `keep: false` — kept for the record, never a class. Either it is not a wearable item
  (`category: null`: cosmetics, food, electronics, shoe parts, gift sets), or it is a
  bundle/multi-item label, or it is too thin to train (`Hat` 3, `Robe` 4, `Umbrellas` 6, …).
  Its `category` is the nearest of the five Categories, which is what the label would
  resolve to if it ever became a class.
* `dataset` — which catalogue the label comes from: `paramaggarwal/fashion-product-images-dataset`
  (Kaggle, `articleType`) or `alexeygrigorev/clothing-dataset` (CC0 bootstrap vocabulary).
  The same label string may appear under both datasets as long as they agree on
  `category`/`name` (`Shorts`, `Hat`); `--labels-only --dataset <id>` picks the right set.
* Categories are exactly the five from `CONTEXT.md`: Tops, Bottoms, Outerwear, Shoes,
  Accessories. Names are the Indonesian display names the scanner shows ("Kaos", "Kemeja",
  "Jeans", "Jaket", "Rok", "Sepatu", "Tas", "Topi", …).

## Licence and data notes

The catalogue's MIT tag is the uploader's claim over their labels; the photographs are
third-party catalogue photography they do not own. Trained weights are therefore coursework
artifacts: not redistributed, not shipped commercially
(`docs/adr/0003-kaggle-catalogue-training-data.md`). `scripts/tflite_io.py` and
`fetch_matting_model.py` install nothing — they read the flatbuffer directly.
