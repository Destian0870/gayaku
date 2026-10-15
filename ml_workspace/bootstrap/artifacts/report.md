# Bootstrap classifier — measured report

**This is the BOOTSTRAP model, not the final one.** `docs/adr/0003` keeps the Kaggle
*Fashion Product Images* catalogue as the training set for the shipped classifier; that
dataset needs Kaggle credentials this machine does not have, so the pipeline is proven
with the CC0 set ADR-0003 already lists as optional augmentation:
`alexeygrigorev/clothing-dataset-small` (CC0-1.0, no attribution). Retrain on the
catalogue before treating any accuracy number here as the product's.

## Exact command

```
python ml_workspace/bootstrap/train_classifier.py --epochs 8
```

## Environment

| item | value |
| --- | --- |
| python | 3.14.6 (C:\Users\ASUS\anaconda3\python.exe) |
| platform | Windows-11-10.0.26200-SP0 |
| torch | 2.14.1+cpu |
| torchvision | 0.29.1+cpu |
| device | cpu (CPU training; 16 torch threads) |
| seed | 42 |
| epochs | 8 (best epoch 8), batch 32, AdamW lr 0.001, wd 0.0001 |
| pretrained | ImageNet (`MobileNet_V3_Small_Weights.IMAGENET1K_V1`) |
| train wall clock | 17.4 min |
| dataset commit | 11961516512414bf9f6c150a832cfd21b54a6b54 (alexeygrigorev/clothing-dataset-small) |
| labels.json sha256 | 2a759c7e01cb16174e41ac611324d8feaed60646f4aabeeaaf91d140163f9413 |
| checkpoint sha256 | 442cbb26e479c177044e4f1619e43c009aa3aa3cd6dff91c022746beb3e90fcc |

Data: 3068 train / 341 validation / 372 test images, 10 classes.
Augmentation: RandomCrop(224) after Resize(256), horizontal flip, rotation ±10°, colour jitter
(0.2/0.2/0.2/0.02). Evaluation: Resize(256), CenterCrop(224), no augmentation.

## Class order (this IS the model's output order)

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
| validation | 0.9091 | 341 |
| test | 0.9194 | 372 |

### Per-class accuracy — test

| class | support | correct | recall |
| --- | --- | --- | --- |
| T-Shirt | 52 | 45 | 0.865 |
| Shirt | 26 | 21 | 0.808 |
| Longsleeve | 72 | 65 | 0.903 |
| Outwear | 38 | 35 | 0.921 |
| Dress | 15 | 15 | 1.000 |
| Skirt | 12 | 11 | 0.917 |
| Pants | 42 | 42 | 1.000 |
| Shorts | 30 | 27 | 0.900 |
| Shoes | 73 | 70 | 0.959 |
| Hat | 12 | 11 | 0.917 |

### Per-class accuracy — validation

| class | support | correct | recall |
| --- | --- | --- | --- |
| T-Shirt | 81 | 79 | 0.975 |
| Shirt | 29 | 25 | 0.862 |
| Longsleeve | 49 | 45 | 0.918 |
| Outwear | 24 | 20 | 0.833 |
| Dress | 32 | 25 | 0.781 |
| Skirt | 12 | 8 | 0.667 |
| Pants | 49 | 47 | 0.959 |
| Shorts | 25 | 23 | 0.920 |
| Shoes | 26 | 25 | 0.962 |
| Hat | 14 | 13 | 0.929 |

## Confusion matrix — test (rows true, columns predicted)

| true \ pred | T-Shirt | Shirt | Longsleeve | Outwear | Dress | Skirt | Pants | Shorts | Shoes | Hat | recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **T-Shirt** | 45 | 0 | 5 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0.865 |
| **Shirt** | 2 | 21 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0.808 |
| **Longsleeve** | 1 | 3 | 65 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0.903 |
| **Outwear** | 0 | 0 | 2 | 35 | 0 | 0 | 1 | 0 | 0 | 0 | 0.921 |
| **Dress** | 0 | 0 | 0 | 0 | 15 | 0 | 0 | 0 | 0 | 0 | 1.000 |
| **Skirt** | 1 | 0 | 0 | 0 | 0 | 11 | 0 | 0 | 0 | 0 | 0.917 |
| **Pants** | 0 | 0 | 0 | 0 | 0 | 0 | 42 | 0 | 0 | 0 | 1.000 |
| **Shorts** | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 27 | 0 | 0 | 0.900 |
| **Shoes** | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | 70 | 1 | 0.959 |
| **Hat** | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 11 | 0.917 |

## Confusion matrix — validation (rows true, columns predicted)

| true \ pred | T-Shirt | Shirt | Longsleeve | Outwear | Dress | Skirt | Pants | Shorts | Shoes | Hat | recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **T-Shirt** | 79 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0.975 |
| **Shirt** | 0 | 25 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0.862 |
| **Longsleeve** | 0 | 1 | 45 | 1 | 0 | 0 | 0 | 2 | 0 | 0 | 0.918 |
| **Outwear** | 0 | 1 | 2 | 20 | 1 | 0 | 0 | 0 | 0 | 0 | 0.833 |
| **Dress** | 0 | 1 | 3 | 1 | 25 | 0 | 0 | 1 | 0 | 1 | 0.781 |
| **Skirt** | 0 | 0 | 2 | 0 | 0 | 8 | 0 | 2 | 0 | 0 | 0.667 |
| **Pants** | 0 | 0 | 0 | 0 | 0 | 0 | 47 | 2 | 0 | 0 | 0.959 |
| **Shorts** | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 23 | 0 | 0 | 0.920 |
| **Shoes** | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 25 | 0 | 0.962 |
| **Hat** | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 13 | 0.929 |

## Training curve

| epoch | train loss | val accuracy | seconds |
| --- | --- | --- | --- |
| 1 | 0.8927 | 0.7977 | 180 |
| 2 | 0.4632 | 0.8651 | 129 |
| 3 | 0.3601 | 0.8563 | 142 |
| 4 | 0.2724 | 0.8798 | 121 |
| 5 | 0.1892 | 0.8944 | 115 |
| 6 | 0.1549 | 0.8739 | 112 |
| 7 | 0.1093 | 0.9032 | 112 |
| 8 | 0.0860 | 0.9091 | 111 |

## Conversion fidelity (filled in by `export_tflite.py`)

The PyTorch reference on the shared held-out subset is **0.9385** over
179 test images (20 per class, seed 42, the same
files `artifacts/subset_predictions.json` records). `export_tflite.py` appends the
converted `.tflite`'s accuracy on that identical list below; a converted model that scores
near chance means the conversion is broken and must not ship.

<!-- export-tflite-section -->

## Converted model (.tflite) fidelity check

Two steps: the ONNX audit copy (torch) and the LiteRT export (TensorFlow + onnx2tf).

### Step 1 — ONNX audit copy

```
torch.onnx.export (dynamo=False), opset 17, 6129287 bytes, sha256 702f9ad5d8a38a6909a0e3b5492fd193a1dc9fab1a3c1ab13e19105ed68f0436
input  image [1, 3, 224, 224]   (NCHW — transposed to NHWC by the converter)
output scores [1, 10]
first ops: Sub(/inner/Sub), Div(/inner/Div), Conv(/inner/backbone/features/features.0/features.0.0/Conv)
onnxruntime vs torch: max abs diff 2.682e-07,
  max |sum(probabilities) - 1| 1.192e-07
```

The first two ops are the normalisation (`Sub`, `Div`), i.e. callers feed raw `[0,1]` pixels,
and the graph ends in a softmax — the app uses the winning score as its `confidence`
(`scan_pipeline.dart`), so logits would be wrong.

### Step 2 — conversion

```
"D:\repo\github\kmilaz\gayaku\ml_workspace\bootstrap\.venv-convert\Scripts\python.exe" ml_workspace/bootstrap/export_tflite.py tflite
```

Environment: D:\repo\github\kmilaz\gayaku\ml_workspace\bootstrap\.venv-convert\Scripts\python.exe, python 3.14.6, tensorflow 2.22.0-rc0,
onnx 1.23.2, onnx2tf 1.28.8 (`convert(..., batch_size=1)`), converter
sample data supplied locally (see README).

### Tensor IO, read from the exported flatbuffer

```
D:\repo\github\kmilaz\gayaku\ml_workspace\bootstrap\artifacts\garment_classifier.tflite
  flatbuffer TFL3, schema v3, producer 'MLIR Converted.'
  6129368 bytes, sha256 4dea19d6b3dbe30bd5a8dc9686803afdd657e9dedbf234d0fd61e5a6be313457
  115 operators in subgraph 0 of 1
  input 0: name='image' shape=[1, 224, 224, 3] dtype=float32
  output 0: name='Identity' shape=[1, 10] dtype=float32
```

### Measured top-1 accuracy on the shared held-out subset

| model | accuracy | images |
| --- | --- | --- |
| PyTorch float32 (reference) | 0.9385 | 179 |
| converted `.tflite` | 0.9385 | 179 |

Same 179 files, same list order, same preprocessing — `artifacts/subset_predictions.json`
records the PyTorch side, `artifacts/tflite_predictions.json` the converted side.

* per-image top-1 agreement with PyTorch: 1.0000
* largest softmax probability deviation from PyTorch: 0.2721
* largest `sum(probabilities) - 1` error (softmax really is the last op): 1.788e-07
* gate: accuracy >= 0.50 and >= PyTorch - 0.10 → PASSED
* shipped copy: `flutter_app/assets/models/garment_classifier.tflite` (4dea19d6b3dbe30bd5a8dc9686803afdd657e9dedbf234d0fd61e5a6be313457)

| class (test subset) | images | PyTorch accuracy | .tflite accuracy | top-1 agreement |
| --- | --- | --- | --- | --- |
| dress | 15 | 1.000 | 1.000 | 1.000 |
| hat | 12 | 0.917 | 0.917 | 1.000 |
| longsleeve | 20 | 0.900 | 0.900 | 1.000 |
| outwear | 20 | 0.950 | 0.950 | 1.000 |
| pants | 20 | 1.000 | 1.000 | 1.000 |
| shirt | 20 | 0.850 | 0.850 | 1.000 |
| shoes | 20 | 0.950 | 0.950 | 1.000 |
| shorts | 20 | 1.000 | 1.000 | 1.000 |
| skirt | 12 | 0.917 | 0.917 | 1.000 |
| t-shirt | 20 | 0.900 | 0.900 | 1.000 |

Model file: 6129368 bytes, sha256 4dea19d6b3dbe30bd5a8dc9686803afdd657e9dedbf234d0fd61e5a6be313457.
The Dart class list is generated from `bootstrap/artifacts/classes.json` (see README's codegen
rule), so its length must equal 10 — `scan_pipeline.dart` refuses to run otherwise.
