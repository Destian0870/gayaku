# ml_workspace — the offline model lab

Offline work only: dataset gathering, training, evaluation, export. The app ships the
resulting `.tflite` files and runs them on device; nothing here runs at runtime
(`docs/adr/0001-scanner-inference-on-device.md`). Decisions that bound this folder:
`0002` (permissive model licences only), `0003` (the Kaggle catalogue is the training data),
`0005` (matte the photo, then classify the cutout) and `0009` (a detector finds the boxes, so a
photo may hold several garments).

## Layout

| Path | Committed? | What it is |
|---|---|---|
| `labels.json` | yes | semantic source of truth: one entry per catalogue `articleType` (143 of them) plus the CC0 bootstrap vocabulary, each with `category`, Indonesian `name`, `keep` and the `dataset` it belongs to |
| `artifacts/classes.json` | yes | the catalogue classifier's class list. **`labels[i]` is the label score `i` means** — this file *is* the model's output order. The CC0 bootstrap export carries its own list at `bootstrap/artifacts/classes.json` (see "Where the models stand") |
| `scripts/prepare_data.py` | yes | Kaggle download, label cleanup, stratified 80/10/10 split, writes `artifacts/classes.json` |
| `scripts/merge_datasets.py` | yes | the 18-class merged set: dedupes the CC0 clone against `Clothes_Dataset`, maps the labels, splits per source folder, writes the ImageFolder, `manifest.csv`, `conflicts.csv` and `yolo/artifacts/{merged_dataset,classes_merged}.json` |
| `scripts/gen_dart_labels.py` | yes | emits `flutter_app/lib/logic/garment_labels.dart` from `classes.json` + `labels.json` |
| `scripts/fetch_matting_model.py` | yes | fetches + verifies `flutter_app/assets/models/u2netp_320.tflite` |
| `scripts/tflite_io.py` | yes | reads a `.tflite`'s tensor IO with no TensorFlow/LiteRT install (tiny flatbuffers reader) |
| `kaggle/fashion_classifier.ipynb` | yes | the training venue: MobileNetV3-small, evaluation, ONNX + TFLite export |
| `data/` | no | downloaded catalogue, `train.csv`/`val.csv`/`test.csv`, `data/split_summary.json` |
| `artifacts/garment_classifier.*`, `artifacts/report.md` | produced | exported model, ONNX audit copy, metrics report |

## Contracts

**Classifier** — input `[1,224,224,3]` float32 NHWC RGB in `[0,1]`; ImageNet normalisation
is baked into the exported graph by a wrapper module, so callers feed raw `[0,1]` pixels.
Output `[1,N]` float32 softmax, class order = `garmentCategories` in the generated Dart file
= `labels` in the class list. Tensor *names* are the converter's business (the ONNX export
says `image`/`scores`, the bootstrap TFLite says `image`/`Identity`), because the app
addresses tensors by index — shape, dtype and that class order are what bind.

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

The generator also reads the shipped `flutter_app/assets/models/garment_classifier.tflite`
and **exits non-zero when the model scores a different number of classes than the list has
labels** (`--model` points it elsewhere; a missing file only prints a note). That is what
stops a list and the weights it describes from drifting apart: you cannot regenerate the Dart
file for a model you have not actually swapped in, and you cannot swap weights without
regenerating the file in the same commit.

## The merged 18-class training set

The classifier's next training set is neither source on its own
(`docs/adr/0008-merge-the-two-training-sources.md`). `Clothes_Dataset` has the Indonesian labels
and the fine outerwear split but no Shoes and no Hat; the CC0 clone has both, and its photographs
are 400 px. `scripts/merge_datasets.py` combines them:

| | |
|---|---|
| classes | 18: the 15 `Clothes_Dataset` folders plus `Kaos_Lengan_Panjang`, `Sepatu`, `Topi` from CC0 |
| unique photographs | **9,728** after dedupe (7,350 from `Clothes_Dataset`, 2,378 from CC0) |
| files scanned | 11,281 — the sources are not disjoint |

The 1,401 photographs that both sources hold (same picture, resized) are the reason a plain copy
into one folder would not work: they would sit in `train` from CC0 and in `test` from
`Clothes_Dataset`, and the test accuracy would measure memorisation. The script therefore groups
photographs by `sha256`, by shared basename plus a 16×16 greyscale signature, and by a 64-bit
dHash, then keeps one member per group:

* **duplicate, same class** — one copy survives (the larger file; on a tie, `--prefer-source`);
* **duplicate, different class across sources** — the copy from `--prefer-source` survives and its
  label wins. The default is `clothes`: it keeps the 15 `Clothes_Dataset` classes at 500, it carries
  the UI vocabulary, and it holds 2.3× the pixels. 403 CC0 `longsleeve` photographs therefore count
  as `Sweter`, which is why `Kaos_Lengan_Panjang` holds 172 photographs. **This is not only a
  display change**: `Longsleeve` is Tops in `labels.json` and `Sweter` is Outerwear, so those 403
  photographs move to another wardrobe tab and reach the outfit matcher under a different Category.
  Rerun with `--prefer-source cc0` to reverse it — `Sweter` then holds 93 and `Kaos_Lengan_Panjang`
  575 — without touching code.
* **duplicate, different class inside one source** — ambiguous, so every member is dropped and the
  group is listed in `conflicts.csv`. Identical photographs filed under `Jaket`, `Kemeja` and
  `Polo` claim two of those labels are wrong, and picking one would invent an answer.

Splits are decided per source folder, never per photograph: CC0 keeps the `train` / `validation` /
`test` split it ships with and each `Clothes_Dataset` class folder is shuffled once with
`--seed 20261022`. The script refuses to write a tree in which a duplicate group, a `sha256`, a
basename or a `phash` reaches two splits — those are assertions, not warnings, because a leak here
only shows up as an accuracy number that looks better than the model is.

`manifest.csv` carries every scanned photograph, dropped ones included, with `source`, `sha256`,
`phash`, `kept`, `reason`, `class_after` and `split`; `conflicts.csv` carries one row per member of
every duplicate group. Both live in the git-ignored output directory, and the committed evidence is
`yolo/artifacts/merged_dataset.json` (per-class counts, mapping, decisions, assertions) plus
`yolo/artifacts/classes_merged.json` (the class order `sorted()` produces, which is what ultralytics
derives from folder names).

## Where the models stand

| Slot | Asset | Class list | State |
|---|---|---|---|
| Matting | `flutter_app/assets/models/u2netp_320.tflite` | — | shipped |
| Classifier | `flutter_app/assets/models/garment_classifier.tflite` | `bootstrap/artifacts/classes.json` (10 CC0 classes) | shipped: the `alexeygrigorev/clothing-dataset-small` bootstrap export, which makes the scanner verifiable end to end today |
| Classifier, merged | same path, new weights | `yolo/artifacts/classes_merged.json` (18 merged classes) | **trained locally on this CPU** (`yolo/train_local.py`, 27 epochs, 2.3 h): test top-1 **81.55 %**, top-5 98.08 %, macro-F1 **0.7968** over 992 photographs; the export passes the app contract but is **not** swapped into `flutter_app/assets/models/` yet |
| Classifier, final | same path, new weights | `artifacts/classes.json` (80 catalogue classes) | pending the Kaggle run; `docs/adr/0003` makes that the final model |

Landing the Kaggle model means replacing the asset **and** regenerating the Dart file in the
same commit. Until that swap, the default class list (80) and the shipped asset (10)
deliberately disagree, and the generator refuses that pair with the drift message above
instead of quietly writing a Dart file that mislabels every prediction.

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

# 3c. the 18-class merged set: dedupe, map, split, write the ImageFolder + evidence
#     ~3 minutes; needs the CC0 clone on disk and Clothes_Dataset/ next to the repo
python ml_workspace/scripts/merge_datasets.py
python ml_workspace/scripts/merge_datasets.py --prefer-source cc0 --force   # the other label choice
python ml_workspace/scripts/merge_datasets.py --limit-per-class 40 --link copy --out .amp/in/scratch  # smoke

# 4. train + export on Kaggle (GPU + Internet, inputs: the catalogue and this labels.json)
#    upload ml_workspace/kaggle/fashion_classifier.ipynb, run all; it writes
#    artifacts/{garment_classifier.tflite,garment_classifier.onnx,classes.json,report.md}

# 5. regenerate the Dart label file after every export (idempotent; --check for CI/pre-commit)
python ml_workspace/scripts/gen_dart_labels.py
python ml_workspace/scripts/gen_dart_labels.py --check
# ... for the CC0 bootstrap model that is shipped today (see "Where the models stand")
python ml_workspace/scripts/gen_dart_labels.py --classes ml_workspace/bootstrap/artifacts/classes.json
# ... for the merged 18-class model, once its .tflite is in place
python ml_workspace/scripts/gen_dart_labels.py --classes ml_workspace/yolo/artifacts/classes_merged.json

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
  (Kaggle, `articleType`), `alexeygrigorev/clothing-dataset` (CC0 bootstrap vocabulary), or
  `ryanbadai/clothes-dataset` (`Clothes_Dataset/` folders). The same label string may appear under
  two datasets as long as they agree on `category`/`name` (`Shorts`, `Hat`);
  `--labels-only --dataset <id>` picks the right set.
* `dataset: gayaku/merged` — the three labels only the merged run has: `Kaos_Lengan_Panjang`
  (Tops), `Sepatu` (Shoes), `Topi` (Accessories). `Clothes_Dataset` has no footwear, headwear or
  long-sleeve class, and the CC0 rows carry English spellings (`Longsleeve`, `Shoes`, `Hat`) that
  the shipped 10-class model uses, so the merged class list names those three in the language the
  UI shows and maps the CC0 folder to it (`scripts/merge_datasets.py`, `docs/adr/0008`).
* Categories are exactly the five from `CONTEXT.md`: Tops, Bottoms, Outerwear, Shoes,
  Accessories. Names are the Indonesian display names the scanner shows ("Kaos", "Kemeja",
  "Jeans", "Jaket", "Rok", "Sepatu", "Tas", "Topi", …).
* One-piece garments and named sets have no honest slot among those five, so they resolve to
  the nearest one: `Dresses`/`Dress`, `Sarees`, `Jumpsuit`, `Nightdress`, `Rompers`,
  `Lehenga Choli`, `Kurta Sets`, `Night suits` and `Tracksuits` all map to **Tops**. A dress
  landing on "Tops" is a modelling compromise, not an oversight — giving one-piece garments
  their own Category is a product decision (it would change `CONTEXT.md`, the five Categories
  and every filter that reads them), and until someone makes it, its `garmentLabelCategory`
  entry stays `Tops` by design. The bootstrap training report flags the visible case
  (`Dress`) on the shipped 10-class model.

## Licence and data notes

The catalogue's MIT tag is the uploader's claim over their labels; the photographs are
third-party catalogue photography they do not own. Trained weights are therefore coursework
artifacts: not redistributed, not shipped commercially
(`docs/adr/0003-kaggle-catalogue-training-data.md`). `scripts/tflite_io.py` and
`fetch_matting_model.py` install nothing — they read the flatbuffer directly.
