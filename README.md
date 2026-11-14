# liveness

On-device face liveness and face matching for Flutter apps. Used by
Solace's identity check, and available to any app in this workspace.

- **`FaceLiveness.show`** opens a full-screen camera flow. It asks for
  random gestures (blink, smile, turn left or right, open mouth, shake
  head) and returns a `LivenessResult` with the frames it captured.
- **`LivenessController`** + **`LivenessPreview`** are the same check
  without the screen, for an app that draws its own (see "Your own
  screen" below).
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

## App setup (required — release builds break without it)

Both bugs below show only in release builds; debug and `flutter run`
work, which is how they slipped through in Solace. They're fixed in each
app's own project files, not in this package.

**Both platforms:** camera permission — `NSCameraUsageDescription` in
`ios/Runner/Info.plist`, `android.permission.CAMERA` in
`android/app/src/main/AndroidManifest.xml`.

**iOS**

- Swift Package Manager must be on. Since 1.4.0, ML Kit
  (`google_mlkit_face_detection` 1.0) ships only a Swift package, with no
  podspec, so it cannot build through CocoaPods. In the app's
  `pubspec.yaml`:

  ```yaml
  flutter:
    config:
      enable-swift-package-manager: true
  ```

  Plugins that still lack SPM support keep building with CocoaPods
  alongside it.
- Minimum iOS 15.0 (ML Kit): `IPHONEOS_DEPLOYMENT_TARGET` in the Runner
  project, and `platform :ios` in `ios/Podfile` if there is one.
- Release stripping can remove `TfLiteModelCreate` (TensorFlow Lite is
  reached over FFI, looked up at runtime), and the face match then fails
  with "Failed to lookup symbol 'TfLiteModelCreate'". `flutter_litert`
  ships an anchor meant to keep these symbols, but until that is proven
  in a release build, keep stripping off for them. At the end of
  `post_install` in `ios/Podfile`:

  ```ruby
  runner_project = Xcodeproj::Project.open(
    File.join(File.dirname(File.realpath(__FILE__)), 'Runner.xcodeproj'),
  )
  runner_project.targets.each do |target|
    next unless target.name == 'Runner'
    target.build_configurations.each do |config|
      next unless %w[Release Profile].include?(config.name)
      config.build_settings['DEAD_CODE_STRIPPING'] = 'NO'
      config.build_settings['STRIP_STYLE'] = 'non-global'
      config.build_settings['STRIP_INSTALLED_PRODUCT'] = 'NO'
    end
  end
  runner_project.save
  ```

  Check the archived binary:
  `nm -gU build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Runner | grep TfLiteModelCreate`
  must print a `T _TfLiteModelCreate` line.
- Upgrading from 1.3.0 or earlier: delete any
  `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` those versions needed in
  `ios/Podfile` and the Runner project. ML Kit's Swift package has an
  arm64 simulator slice, and the iOS 26+ simulators on Apple Silicon
  require arm64.
- Upgrading from 1.2.0 or earlier: delete the `TensorFlowLiteSwift` shim
  those versions needed — `ios/podspecs/TensorFlowLiteSwift/` and the
  `pod 'TensorFlowLiteSwift', :path => ...` line in `ios/Podfile` — then
  run `pod install`. `flutter_litert` downloads its own prebuilt
  TensorFlow Lite frameworks (about 85 MB, once, cached afterwards) and
  depends on no TensorFlow pod, so a leftover shim would link a second
  copy of `TensorFlowLiteC`. Run the face match on a device afterwards,
  not just the camera.

**Android** (`android/app/build.gradle.kts`, inside `android { }`)

```kotlin
packaging {
    jniLibs {
        pickFirsts.add("**/libc++_shared.so") // camera and tflite both ship it
        useLegacyPackaging = true
    }
}
androidResources {
    noCompress += listOf("tflite", "emd", "tfl", "pb") // models stay uncompressed
}
buildTypes {
    release {
        // R8 may stay on, with keep rules for ML Kit and TensorFlow Lite
        // in proguard-rules.pro (Solace's android/app/proguard-rules.pro
        // is a working set); Google Play's release check wants the DEX
        // obfuscated. Without those rules, turn it off:
        // isMinifyEnabled = false
        isShrinkResources = false
    }
}
```

And in the main `<activity>` of `AndroidManifest.xml` (Impeller has
camera-preview texture problems on some devices):

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
```

Test a release build on a real Android phone and an archived build on a
real iPhone, through the face match, not just the camera opening.

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

## Your own screen

`FaceLiveness.show` draws the package's own screen. To draw your own,
drive a `LivenessController` and rebuild from its state:

```dart
final controller = LivenessController(
  config: const LivenessConfig(
    requiredGestures: [LivenessGesture.turnLeft, LivenessGesture.smile],
    rejectMultipleFaces: true,
  ),
);
controller.initialize(); // opens the camera; failures show in state.error
controller.start();      // countdown, a 2 s "get ready", then the gestures

// In build():
Stack(children: [
  LivenessPreview(controller: controller), // camera only, cover-cropped
  ValueListenableBuilder<LivenessState>(
    valueListenable: controller,
    builder: (context, state, _) => YourOverlay(state),
  ),
]);

final result = await controller.result; // same LivenessResult as show()
controller.dispose();
```

`LivenessState` has `phase` (`preparing`, `gesture`, `finalCapture`,
`completing`, `finished`), `cameraReady`, `gestures` (the order chosen for
this session), `currentIndex`, `currentGesture`, `gestureProgress` (0–1
into the current gesture, e.g. how far the head has turned), `completed`,
`hint` (during `preparing` and `finalCapture`: what to fix — no face, move
closer, centre, light — or null when the frame is good), `faceCount`,
`timeRemaining`/`timeoutSeconds`, `error` and `result`. Faces are tracked
from the moment the camera is ready, so the "get ready" pause can already
say "face found" or "move closer"; no gesture counts until it ends. Map
the enums to your own wording; the package's English is only used by its
own screen. `cancel()` ends the session; disposing an unfinished one
completes `result` as cancelled.

If your face guide isn't vertically centred, tell the framing check where
it is: `LivenessThresholds(faceCenterTargetY: 0.43)` for a guide whose
centre is 43% down a full-screen preview (the default is 0.5).

With `rejectMultipleFaces: true`, a frame with more than one face counts
for nothing and the hint becomes `LivenessCaptureHint.multipleFaces`. It's
off by default, which keeps the original behaviour.

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
