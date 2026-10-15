# Scanner inference runs on-device; ml_workspace stays an offline lab

The Smart Scanner runs its models inside the Flutter app as bundled LiteRT (`.tflite`) assets through `tflite_flutter`. `ml_workspace/` holds only offline work: dataset gathering, training, evaluation and export. A Python API serving predictions was rejected because it needs a host and a reachable network during the demo; a hybrid (matting local, classification remote) pays both integration costs.

## Consequences

- Models ship inside the APK, so the release manifest keeps zero `INTERNET` permission and the scanner works with no connectivity.
- Swapping a model means a new build, not a redeploy.
- LiteRT export runs on Linux/macOS only, so exports happen in WSL or Colab even though the app is developed on Windows.
- Inference can only be verified on the Android emulator or a device; Windows desktop runs of the app are limited to non-inference behaviour.
