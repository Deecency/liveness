# liveness

On-device face liveness and face matching for Flutter apps. Used by
Solace's identity check, and available to any app in this workspace.

- **`FaceLiveness.show`** opens a full-screen camera flow. It asks for
  random gestures (blink, smile, turn left or right, open mouth, shake
  head) and returns a `LivenessResult` with the frames it captured.
- **`FaceCompare`** turns faces into embeddings with a TFLite model and
  scores how alike two faces are: `compare`, `compareBest` (a reference
  photo against several live frames), `compareDetailed`, `isSamePerson`.

Faces are found with ML Kit. Everything runs on the phone; nothing is
uploaded.

## Using it

The package is a private GitHub repo, `Deecency/liveness`. Add it at a
tagged version:

```yaml
dependencies:
  liveness:
    git:
      url: https://github.com/Deecency/liveness.git
      ref: v1.0.0
```

Fetching it needs git access to the repo (the machine's GitHub sign-in).
An app moves to a newer version only when its `ref` changes.

To try unreleased changes from a local copy beside the app, add a
`pubspec_overrides.yaml` to the app, and keep it out of git:

```yaml
dependency_overrides:
  liveness:
    path: ../liveness
```

The app needs camera permission: `NSCameraUsageDescription` in
`ios/Runner/Info.plist`, and `android.permission.CAMERA` in
`android/app/src/main/AndroidManifest.xml`.

```dart
import 'package:liveness/liveness.dart';

final result = await FaceLiveness.show(
  context,
  config: const LivenessConfig(randomGestureCount: 2, timeoutSeconds: 60),
);
if (result?.status == LivenessResultStatus.success) {
  final faceCompare = await FaceCompare.create();
  // Score result's frames against a reference photo.
}
```

## Models

`FaceModel.mobileFaceNet` (about 5 MB, the default) and
`FaceModel.faceNet` (about 24 MB) are bundled. `FaceModel.faceNet512` is
listed, but its model file isn't bundled: choosing it fails until
`assets/models/facenet_512.tflite` is added back.

## Changing it

This package is shared. To release a change: commit it, tag a new
version (`git tag -a v1.1.0 -m "..." && git push origin v1.1.0`), then
bump `ref` in each app that should get it. Keep the API backward
compatible, so apps can move up one at a time.

## Origin and licence

Started from Widiyanto Ramadhan's
[face_match_liveness](https://github.com/widiramadhan/face_match_liveness)
(MIT, see [LICENSE](LICENSE)), then substantially reworked for Solace's
identity check: capture, gestures, thresholds and matching.
