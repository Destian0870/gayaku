# The shipped classifier on the app's own photos

Answers one question: does the model recognise anything, or does it just answer
`Pants`? Run it with

```bash
ml_workspace/bootstrap/.venv-convert/Scripts/python.exe ml_workspace/scripts/classify_assets.py --markdown
```

Model: `flutter_app/assets/models/garment_classifier.tflite`, sha256
`4dea19d6b3dbe30bd5a8dc9686803afdd657e9dedbf234d0fd61e5a6be313457`, 10 classes
(the CC0 bootstrap set — see `ml_workspace/bootstrap/README.md`; ADR-0003 keeps
the Kaggle catalogue as the final training set). Class order:
`ml_workspace/bootstrap/artifacts/classes.json`.

| Foto | Label | Category | Nama | Keyakinan |
|---|---|---|---|---|
| `beige_trench.jpg` | T-Shirt | Tops | Kaos | 76.6% |
| `beige_trench_denim.png` | Longsleeve | Tops | Kaos Lengan Panjang | 35.3% |
| `classic_sneakers.jpg` | Shoes | Shoes | Sepatu | 99.5% |
| `gold_chain.png` | Skirt | Bottoms | Rok | 50.4% |
| `gold_link_chain.jpg` | Hat | Accessories | Topi | 77.5% |
| `leather_loafers.jpg` | Shoes | Shoes | Sepatu | 100.0% |
| `linen_office_set.jpg` | T-Shirt | Tops | Kaos | 36.8% |
| `linen_shirt.jpg` | Pants | Bottoms | Celana Panjang | 43.7% |
| `minimal_watch.jpg` | Shoes | Shoes | Sepatu | 66.3% |
| `pleated_midi_skirt.jpg` | Dress | Tops | Gaun | 100.0% |
| `silk_blouse.png` | Shirt | Tops | Kemeja | 99.9% |
| `straight_leg_jeans.jpg` | Pants | Bottoms | Celana Panjang | 94.0% |
| `tailored_trousers.jpg` | Pants | Bottoms | Celana Panjang | 96.6% |
| `todays_look.png` | Longsleeve | Tops | Kaos Lengan Panjang | 35.3% |
| `tote_bag_canvas.jpg` | Longsleeve | Tops | Kaos Lengan Panjang | 53.7% |
| `white_sneakers.png` | Shoes | Shoes | Sepatu | 99.9% |

## Reading it

- **Single garments the bootstrap set covers are recognised confidently** and
  across Categories, not just `Pants`: blouse → `Shirt`/Kemeja 99.9%, loafers
  100%, sneakers 99.9%, jeans 94.0%, trousers 96.6%. The `Pants` bias was a fear,
  not a finding.
- **Accessories are a class-list gap, not a model failure.** The CC0 set has no
  bag/watch/necklace classes, so a tote bag or a watch can only be answered with
  a garment label (`Tote Bag` → Longsleeve 53.7%, `Minimal Watch` → Shoes 66.3%).
  The catalogue run adds `Handbags` 1759, `Wallets` 928, `Watches` 2542,
  `Sunglasses` 1073.
- **Worn or multi-garment photos stay unreliable** (trench on a model →
  T-Shirt 76.6%, a rail of shirts → Pants 43.7%): training data is one garment per
  frame, which is also what ADR-0005 assumes at capture time.
- **Failure shows up as low confidence, not as silence.** There is no
  "not a garment" class, so out-of-distribution input still returns a label: on
  the emulator a screenshot of the app itself came back as `Shoes` at 98%. Treat
  the confidence line in the review screen as a hint, and the Correction step as
  the guard.
- `pleated_midi_skirt.jpg` is a worn skirt read as `Dress`/Gaun 100% — the CC0
  set has no separate skirt-on-a-model case, and one-piece garments map to Tops
  (documented in `ml_workspace/README.md`).

## Caveat on method

This sweep classifies the photo directly, while the app classifies the **Cutout**.
For a photo whose garment fills the frame the two agree; for a cluttered photo the
matting step changes what the classifier sees. The on-device scan therefore stays
the authoritative check, and this table is the broad, repeatable one.

## On-device, Pixel 9 emulator, shipped debug build

Photos pushed to the emulator gallery and scanned through the real screen
(camera/gallery → matting → classify the Cutout → K-Means colour → review):

| Foto | Category | Warna | Nama | Terdeteksi | Keyakinan |
|---|---|---|---|---|---|
| `silk_blouse.png` — shirt on a hanger, plain background | Tops | Cokelat | Kemeja | Shirt | 100% |
| `classic_sneakers.jpg` — pair of trainers | Shoes | Krem | Sepatu | Shoes | 100% |
| `straight_leg_jeans.jpg` — jeans on white | Bottoms | Beige | Celana Panjang | Pants | 91% |
| `pleated_midi_skirt.jpg` — skirt **worn by a model** | Tops | Beige | Gaun | Dress | 52% |

The first three are the intended capture condition — one garment, plain
background — and they land in three different Categories, so the scanner is not a
`Pants` detector; the Cutouts are clean enough that the shirt's sleeves and the
sneakers' laces survive. The fourth is out of contract: a worn garment breaks the
matting step (it cut a vertical strip of the model instead of the skirt), which
feeds the classifier a shape it reads as a dress. 52% confidence is the visible
warning, and the `Dress → Tops` Category mapping is recorded in
`ml_workspace/README.md`.
