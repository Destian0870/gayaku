# The Carousell clothes dataset joins the training data

**Status**: accepted — adds a second training source alongside ADR-0003, which is not superseded.

The classifier is also trained on Kaggle's `ryanbadai/clothes-dataset`, attached to a Kaggle notebook as an input rather than downloaded: a flat ImageFolder of `Clothes_Dataset/<Kelas>/*.jpg` with 15 Indonesian class folders, ~500 photographs each (~7,500 total, 1.48 GB) and **no train/val split**, so the training notebook builds one. It earns its place on three counts ADR-0003's catalogue does not cover: the labels are already the Indonesian words the UI shows (`Kaos`, `Kemeja`, `Jaket_Denim`, `Celana_Panjang`), they are finer than the catalogue's (denim jacket vs sports jacket vs coat, jeans vs trousers), and the photographs are single-garment listing shots — the same capture condition the app demands (ADR-0005).

## Consequences

- **The five Categories do not cover this dataset.** All 15 classes are Tops, Bottoms or Outerwear (6 / 4 / 5); there is no Shoes and no Accessories class. A model trained only here answers a photographed shoe with a garment label, where today's bootstrap model does recognise Shoes and Hat. Footwear and accessories must keep coming from another source (the catalogue has `Shoes`, `Handbags`, `Wallets`, `Watches`) or be left to the Correction step, and either way it belongs in the report.
- **The dataset carries label noise and overlaps the CC0 set.** At least six files share UUID basenames with `alexeygrigorev/clothing-dataset`, and two of those were relabelled from that dataset's noisy classes (`Not sure`, `Other`) into `Blazer`. Treat the confusion matrix as the evidence, not the headline accuracy.
- **Licence posture is unchanged.** The Kaggle tag says MIT, but the description says the images were scraped from Carousell and states nothing about redistribution. Same as ADR-0003: the weights and any build containing them are coursework artefacts, not for redistribution.
- **Accuracy is not comparable across class counts.** The public baseline for this dataset is a fine-tuned ViT-base at 78.47 % accuracy / 0.7803 macro-F1 over 15 classes; the shipped 10-class bootstrap model measured 91.9 %. Fifteen classes are harder than ten, so neither number refutes the other — any comparison must hold the class list fixed.
- `ml_workspace/labels.json` gained 15 rows tagged `ryanbadai/clothes-dataset`. The codegen refuses two datasets whose shared labels disagree, so `Jeans`, `Polo`, `Hoodie` and `Blazer` deliberately reuse the existing category and display name instead of restating them.

## Considered options

- **The catalogue alone** (ADR-0003): 41,369 photographs over 80 classes including footwear and accessories, but the fine distinctions the scanner is judged on (`Jaket_Denim` vs `Jaket_Olahraga`) do not exist there, and English labels need translating for the UI.
- **`ryanbadai/clothes-dataset` alone**: fastest to a good garment classifier, but silently loses two of the app's five Categories.
- **Both, in one model**: what this ADR sets up — one training set per run, sharing the label table, with the class list that ships determining `garmentCategories`.
