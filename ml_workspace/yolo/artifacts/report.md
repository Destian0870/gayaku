# yolov8n-cls on the merged set — local CPU run

| | |
| --- | --- |
| command | `python ml_workspace/yolo/train_local.py --epochs 30 --batch 32 --name yolov8n-cls-merged-224` |
| dataset | `ml_workspace/data/merged` from `scripts/merge_datasets.py` (`docs/adr/0008`) |
| weights | `yolov8n-cls.pt` |
| training | imgsz 224, 30 epochs, batch 32, seed 42, patience 8, device cpu |
| classes | 18 |

## Measured

| split | top-1 | top-5 | accuracy | macro-F1 | photographs |
| --- | --- | --- | --- | --- | --- |
| val (epoch selection) | 0.8130 | 0.9833 | 0.8130 | 0.8122 | 957 |
| **test (reported)** | **0.8155** | 0.9808 | 0.8155 | **0.7968** | 992 |

Not comparable with the shipped 10-class bootstrap model (91.9 % top-1) or the public 15-class
baseline (78.47 % / 0.7803 on a 40 % split): the class counts and splits differ.

## Per class, split `test`

| class | precision | recall | f1-score | support |
| --- | --- | --- | --- | --- |
| Blazer | 0.6222 | 0.5600 | 0.5895 | 50 |
| Celana_Panjang | 0.7800 | 0.9070 | 0.8387 | 86 |
| Celana_Pendek | 0.9273 | 0.8361 | 0.8793 | 61 |
| Gaun | 0.7639 | 0.9322 | 0.8397 | 59 |
| Hoodie | 0.8627 | 0.8800 | 0.8713 | 50 |
| Jaket | 0.8000 | 0.7529 | 0.7758 | 85 |
| Jaket_Denim | 0.9200 | 0.9200 | 0.9200 | 50 |
| Jaket_Olahraga | 0.6735 | 0.6735 | 0.6735 | 49 |
| Jeans | 0.8864 | 0.7800 | 0.8298 | 50 |
| Kaos | 0.9211 | 0.8974 | 0.9091 | 78 |
| Kaos_Lengan_Panjang | 1.0000 | 0.3333 | 0.5000 | 21 |
| Kemeja | 0.7746 | 0.8462 | 0.8088 | 65 |
| Mantel | 0.6607 | 0.7551 | 0.7048 | 49 |
| Polo | 0.7556 | 0.7556 | 0.7556 | 45 |
| Rok | 0.8846 | 0.7797 | 0.8288 | 59 |
| Sepatu | 0.9863 | 0.9863 | 0.9863 | 73 |
| Sweter | 0.7273 | 0.8000 | 0.7619 | 50 |
| Topi | 0.9091 | 0.8333 | 0.8696 | 12 |

## Per class, split `val`

| class | precision | recall | f1-score | support |
| --- | --- | --- | --- | --- |
| Blazer | 0.5769 | 0.6000 | 0.5882 | 50 |
| Celana_Panjang | 0.7921 | 0.8511 | 0.8205 | 94 |
| Celana_Pendek | 0.9231 | 0.7869 | 0.8496 | 61 |
| Gaun | 0.7460 | 0.7121 | 0.7287 | 66 |
| Hoodie | 0.8654 | 0.9000 | 0.8824 | 50 |
| Jaket | 0.7895 | 0.8451 | 0.8163 | 71 |
| Jaket_Denim | 0.8846 | 0.9200 | 0.9020 | 50 |
| Jaket_Olahraga | 0.8095 | 0.6939 | 0.7473 | 49 |
| Jeans | 0.7818 | 0.8600 | 0.8190 | 50 |
| Kaos | 0.9167 | 0.9565 | 0.9362 | 92 |
| Kaos_Lengan_Panjang | 0.8182 | 0.5625 | 0.6667 | 16 |
| Kemeja | 0.8387 | 0.8000 | 0.8189 | 65 |
| Mantel | 0.7083 | 0.6939 | 0.7010 | 49 |
| Polo | 0.7955 | 0.7778 | 0.7865 | 45 |
| Rok | 0.7742 | 0.8136 | 0.7934 | 59 |
| Sepatu | 1.0000 | 1.0000 | 1.0000 | 26 |
| Sweter | 0.8000 | 0.8000 | 0.8000 | 50 |
| Topi | 1.0000 | 0.9286 | 0.9630 | 14 |

## Confusion matrix, split `test` (rows true, columns predicted)

| true \ predicted | Blazer | Celana_Panjang | Celana_Pendek | Gaun | Hoodie | Jaket | Jaket_Denim | Jaket_Olahraga | Jeans | Kaos | Kaos_Lengan_Panjang | Kemeja | Mantel | Polo | Rok | Sepatu | Sweter | Topi |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Blazer** | 28 | 0 | 0 | 2 | 0 | 1 | 0 | 2 | 0 | 0 | 0 | 2 | 13 | 0 | 2 | 0 | 0 | 0 |
| **Celana_Panjang** | 0 | 78 | 1 | 0 | 0 | 0 | 0 | 0 | 5 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 |
| **Celana_Pendek** | 0 | 8 | 51 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 |
| **Gaun** | 1 | 1 | 0 | 55 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| **Hoodie** | 0 | 0 | 0 | 0 | 44 | 1 | 0 | 4 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| **Jaket** | 2 | 0 | 0 | 0 | 2 | 64 | 2 | 6 | 0 | 0 | 0 | 2 | 3 | 2 | 0 | 0 | 2 | 0 |
| **Jaket_Denim** | 2 | 0 | 0 | 0 | 0 | 1 | 46 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| **Jaket_Olahraga** | 4 | 1 | 0 | 2 | 2 | 7 | 0 | 33 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **Jeans** | 0 | 10 | 0 | 0 | 0 | 0 | 0 | 0 | 39 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| **Kaos** | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 70 | 0 | 0 | 0 | 4 | 0 | 0 | 1 | 0 |
| **Kaos_Lengan_Panjang** | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 2 | 7 | 1 | 0 | 0 | 0 | 0 | 9 | 1 |
| **Kemeja** | 3 | 0 | 0 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 55 | 0 | 2 | 0 | 0 | 1 | 0 |
| **Mantel** | 3 | 0 | 0 | 1 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 2 | 37 | 0 | 2 | 0 | 0 | 0 |
| **Polo** | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 2 | 0 | 1 | 0 | 5 | 0 | 34 | 0 | 0 | 1 | 0 |
| **Rok** | 1 | 1 | 3 | 5 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 46 | 0 | 0 | 0 |
| **Sepatu** | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 72 | 0 | 0 |
| **Sweter** | 1 | 0 | 0 | 1 | 0 | 1 | 1 | 1 | 0 | 2 | 0 | 1 | 0 | 2 | 0 | 0 | 40 | 0 |
| **Topi** | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 10 |

## Photographs per class in the tree

| class | train | val | test |
| --- | --- | --- | --- |
| Blazer | 399 | 50 | 50 |
| Celana_Panjang | 785 | 94 | 86 |
| Celana_Pendek | 473 | 61 | 61 |
| Gaun | 529 | 66 | 59 |
| Hoodie | 399 | 50 | 50 |
| Jaket | 563 | 71 | 85 |
| Jaket_Denim | 399 | 50 | 50 |
| Jaket_Olahraga | 393 | 49 | 49 |
| Jeans | 397 | 50 | 50 |
| Kaos | 797 | 92 | 78 |
| Kaos_Lengan_Panjang | 135 | 16 | 21 |
| Kemeja | 565 | 65 | 65 |
| Mantel | 396 | 49 | 49 |
| Polo | 359 | 45 | 45 |
| Rok | 470 | 59 | 59 |
| Sepatu | 198 | 26 | 73 |
| Sweter | 399 | 50 | 50 |
| Topi | 123 | 14 | 12 |

## Known data problems

* `Kaos_Lengan_Panjang` is a mixed class: a spot check of five photographs found three knitted
  sweaters or cardigans and two long-sleeve tees, and CC0's `longsleeve` folder is where they came
  from (`docs/adr/0008`). Its recall is the number to read first.
* CC0's `outwear` is one wide umbrella mapped to `Jaket`, so it competes with `Jaket_Denim`,
  `Jaket_Olahraga`, `Blazer`, `Mantel` and `Sweter`.
* `Polo` and `Kemeja` each lost 51 photographs that were jacket photographs filed under the wrong
  class inside `Clothes_Dataset`; those classes hold wrong examples less often now, but they are
  smaller.

## Exported model

The `.tflite` export was skipped (`--no-export`). The class order the app must be
generated from is: Blazer, Celana_Panjang, Celana_Pendek, Gaun, Hoodie, Jaket, Jaket_Denim, Jaket_Olahraga, Jeans, Kaos, Kaos_Lengan_Panjang, Kemeja, Mantel, Polo, Rok, Sepatu, Sweter, Topi. Convert `weights/best.onnx` to `.tflite` and
check it against the contract before copying anything into `flutter_app/assets/models/`.

## Licence

Trained with Ultralytics YOLOv8 on CC0 photographs plus `ryanbadai/clothes-dataset`. Ultralytics
states that models trained with their code are AGPL-3.0 by default, and this `.tflite` derives from
the `yolov8n-cls.pt` checkpoint: distributing a build that contains it triggers AGPL-3.0's source
obligation, and this repository has no LICENSE file (`docs/adr/0006`). The Carousell photographs
are not ours to redistribute (`docs/adr/0007`).
