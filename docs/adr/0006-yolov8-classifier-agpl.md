# The classifier is a YOLOv8 classification model, accepting the AGPL-3.0 consequence

**Status**: accepted — supersedes ADR-0002 for the garment classifier only; ADR-0002 still governs the matting model.

The garment classifier is trained with Ultralytics YOLOv8 (`yolov8n-cls`) in a Colab notebook (`ml_workspace/yolo/`) rather than the MobileNetV3-small that `ml_workspace/bootstrap/` trains. The reason is the user's: they want to learn the YOLO toolchain hands-on. Technically it is a drop-in — classification, not detection, so the app's contract is unchanged (one 224 px image in, one probability per label out), and no NMS, bounding boxes or new Flutter plugin are involved. Ultralytics' licence page states that all Ultralytics-trained models are AGPL-3.0 by default, so the exported weights inherit that licence.

## Consequences

- Shipping a build that contains these weights triggers AGPL-3.0's source obligation: the complete corresponding source of the derivative work, weights included, must be offered under AGPL-3.0. This repository has no LICENSE file, so adding one is now a prerequisite for distributing such a build.
- `ultralytics_yolo` (the Flutter plugin, also AGPL-3.0) is **not** a dependency: the app bundles the exported `.tflite` and runs it through `tflite_flutter`. The licence attaches to the training code and the weights, not to our inference glue.
- Publisher-trained weights are not an escape hatch either. `louisJLN/yolo8-fashionpedia` (MIT tag over an Ultralytics base), `HasanKabir23/Yolov26s-DeepFashion2` (Apache tag, Ultralytics-trained) and `kesimeg/yolov8n-clothing-detection` (no licence) are all AGPL-3.0 upstream, and Ultralytics' position covers models produced with their training code as well as their published weights.
- Academic use is unaffected in practice: Ultralytics lists university coursework as free AGPL use. The obligation starts at distribution.

## Considered options

- **Keep the permissive-only rule** (`docs/adr/0002`): MobileNetV3-small trained on the same data, no licence obligation, at the cost of not learning the YOLO toolchain. Rejected by the user, not on technical grounds.
- **A permissively licensed model with the same job**: YOLOX-tiny or TensorFlow's EfficientDet-Lite are Apache-2.0 and would keep the old rule while later allowing multi-garment photos. Not chosen now; the app's pipeline isolates the model behind one interface, so this stays open.
