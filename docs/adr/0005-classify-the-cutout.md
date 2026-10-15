# One garment per photo: matte, then classify the cutout

The scanner accepts a single flat-lay or hanger photo, so it runs no object detector: the matting model produces a Cutout, the classifier reads that Cutout at 224 px, and the Dominant colour is computed from the Cutout's pixels. Matting ships as `u2netp` (Apache-2.0, a pre-exported `.tflite`, ~5–9 MB) because it needs no conversion work and keeps the APK small; BiRefNet_lite (MIT, 114 MB, ONNX→TFLite conversion of our own) is the documented upgrade, gated on measuring edge quality on real photos first.

## Consequences

- A photo containing several garments is out of scope: the matting step would return one merged silhouette.
- Classifying the Cutout rather than the raw photo is what lets white-background training data transfer to a garment photographed on a bed.
- The matting model sits behind one Dart interface, so swapping `u2netp` for BiRefNet_lite changes one asset and its preprocessing, not the pipeline.
