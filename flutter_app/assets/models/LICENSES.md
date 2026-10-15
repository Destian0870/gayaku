# Model licences

Every model bundled in the APK must be Apache-2.0, MIT or BSD (see
`docs/adr/0002-permissive-model-licences.md`). This file records what each shipped `.tflite`
is, where it came from, and what it hashes to. Regenerate the numbers with
`python ml_workspace/scripts/tflite_io.py <file>`.

## `u2netp_320.tflite` — matting

| | |
|---|---|
| Model | U²-Net small (`u2netp`), salient-object / background-removal matting, 320×320 |
| Licence | **Apache-2.0** — © the U²-Net authors |
| Upstream project | https://github.com/xuebinqin/U-2-Net (Apache-2.0) |
| Downloaded from | https://huggingface.co/abhimanyu666/u2nettflite/resolve/main/u2netp.tflite (repository declares `license: apache-2.0`; a format conversion of the upstream weights, no architectural change) |
| sha256 | `558136589a47e97f53944ac3f65ba56f4efb5f6bae8e92b573e7c463d20fdb58` |
| Size | 4,575,464 bytes (4.6 MB) |
| Flatbuffer | TFL3, schema v3, producer `MLIR Converted.`, subgraph 0, 274 operators |
| Input | `serving_default_input.1:0` — `[1, 320, 320, 3]` float32, NHWC RGB in `[0, 1]` |
| Outputs | 7 tensors, all `[1, 320, 320, 1]` float32; output 0 `PartitionedCall:1` is the fused saliency mask in `[0, 1]` |

Get it with `python ml_workspace/scripts/fetch_matting_model.py`. A GitHub-only mirror of
the same conversion: https://github.com/PINTO0309/PINTO_model_zoo (061_U-2-Net).

## `garment_classifier.tflite` — garment classifier

Not in the repository yet; the path is reserved for the export from
`ml_workspace/kaggle/fashion_classifier.ipynb` (or from the local CC0 bootstrap run).
Contract: input `image` NHWC `[1, 224, 224, 3]` float32 RGB in `[0, 1]` with ImageNet
normalisation baked into the graph; output `scores` `[1, N]` softmax whose class order is
`ml_workspace/artifacts/classes.json` / `flutter_app/lib/logic/garment_labels.dart`.

- **Weights trained by us** (torchvision MobileNetV3-small, ImageNet-initialised; the
  torchvision weights are BSD-3-Clause).
- **Training data is the Kaggle Fashion Product Images catalogue whose MIT tag covers
  labels, not the photographs — coursework artifacts, not for redistribution.**
- Optional local bootstrap run trains the same architecture on
  `alexeygrigorev/clothing-dataset` (CC0, label vocabulary recorded in
  `ml_workspace/labels.json` with `dataset: alexeygrigorev/clothing-dataset`); that
  dataset's CC0 claim is likewise over its labels, and it is a coursework artifact too.
- When the classifier lands here, add its sha256 and size to this file.
