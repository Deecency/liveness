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

- Minimum iOS 15.5 (ML Kit): `platform :ios, '15.5'` in `ios/Podfile`
  and `IPHONEOS_DEPLOYMENT_TARGET = 15.5` in the Runner project.
- Release stripping removes `TfLiteModelCreate` (tflite_flutter looks it
  up at runtime with `dlsym`, so nothing references it), and the face
  match fails with "Failed to lookup symbol 'TfLiteModelCreate'". At the
  end of `post_install` in `ios/Podfile`:

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
- Simulator: ML Kit has no arm64 simulator slice. In the `post_install`
  pods loop: `config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'`.
- `pod install` clones the whole TensorFlow repo and can sit there for
  an hour. `tflite_flutter` depends on `TensorFlowLiteSwift`, which has
  no binary release, so CocoaPods clones
  `github.com/tensorflow/tensorflow` to build it from source. Nothing
  uses it: `tflite_flutter` is an FFI plugin that resolves `TfLite*` out
  of the prebuilt `TensorFlowLiteC` xcframework with `dlsym` — the same
  reason the stripping fix above is needed. Point the Swift pod at the C
  one instead, as a local pod so CocoaPods fetches nothing. Create
  `ios/podspecs/TensorFlowLiteSwift/TensorFlowLiteSwift.podspec`:

  ```ruby
  Pod::Spec.new do |s|
    s.name     = 'TensorFlowLiteSwift'
    s.version  = '2.12.0'
    s.summary  = 'Maps onto TensorFlowLiteC; tflite_flutter is FFI-only.'
    s.homepage = 'https://www.tensorflow.org/lite'
    s.license  = { :type => 'Apache-2.0' }
    s.authors  = 'Google Inc.'
    s.platform = :ios, '12.0'

    # Required by the spec validator, never fetched: `:path` below makes
    # this a local pod, so CocoaPods reads this file and downloads nothing.
    # Switching the Podfile to `:podspec` WOULD clone the repo named here,
    # which is the whole thing this shim exists to avoid.
    s.source = {
      :git => 'https://github.com/tensorflow/tensorflow.git',
      :tag => "v#{s.version}",
    }

    s.dependency 'TensorFlowLiteC', '2.12.0'
    s.subspec('Core')   { |c| c.dependency 'TensorFlowLiteC', '2.12.0' }
    s.subspec('Metal')  { |c| c.dependency 'TensorFlowLiteC/Metal', '2.12.0' }
    s.subspec('CoreML') { |c| c.dependency 'TensorFlowLiteC/CoreML', '2.12.0' }
  end
  ```

  Then in the `Runner` target in `ios/Podfile`, above
  `flutter_install_all_ios_pods`:

  ```ruby
  pod 'TensorFlowLiteSwift', :path => 'podspecs/TensorFlowLiteSwift'
  ```

  `:path` is what keeps it local — with `:podspec` CocoaPods still
  downloads the spec's `source`. Keep the version in step with
  `tflite_version` in `tflite_flutter/ios/tflite_flutter.podspec`.
  Because this swaps out a dependency, run the face match on a device
  afterwards, not just the camera.

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
