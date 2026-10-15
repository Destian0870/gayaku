# Only permissively licensed model weights ship

Every model bundled in the APK must be Apache-2.0, MIT or BSD. That rules out the most convenient fashion weights: Ultralytics-trained YOLO models (AGPL-3.0), `mattmdjaga/segformer_b2_clothes` and `sayeed99/segformer-b3-fashion` (NVIDIA non-commercial), BRIA RMBG-2.0 (CC BY-NC 4.0) and `isnet-general-use` (weights never licensed upstream — xuebinqin/DIS#150 is still open). The garment classifier is therefore trained by us and matting uses U-2-Net weights.

## Considered options

- **AGPL-3.0 weights.** Ultralytics' own FAQ makes coursework free, but distributing the artifact would put the whole derivative work, weights included, under AGPL-3.0 — and this repository has no LICENSE file.
- **Non-commercial research weights.** Legal for an academic project, but the artifacts could never leave coursework and the repository would inherit non-commercial terms.
