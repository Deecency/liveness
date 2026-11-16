import 'package:liveness/shared/l10n/liveness_localizations.dart';
import 'package:liveness/shared/models/enums.dart';

/// The screen's words in English. Extend it to change some of them and
/// keep the rest.
class LivenessLocalizationsEn extends LivenessLocalizations {
  const LivenessLocalizationsEn();

  @override
  String get title => 'Liveness Verification';

  @override
  String get initializingCamera => 'Initializing camera…';

  @override
  String get preparingTitle => 'Preparing Verification';

  @override
  String get preparingSubtitle =>
      'Liveness verification will start automatically in a few seconds…';

  @override
  String get successTitle => 'Verification Successful!';

  @override
  String get successSubtitle =>
      'All gestures verified. Processing your result…';

  @override
  String secondsRemaining(num seconds) => '${seconds}s remaining';

  @override
  String gestureName(LivenessGesture gesture) => switch (gesture) {
    LivenessGesture.blink => 'Blink',
    LivenessGesture.mouthOpen => 'Open Mouth',
    LivenessGesture.headShake => 'Shake Head',
    LivenessGesture.smile => 'Smile',
    LivenessGesture.turnLeft => 'Turn Left',
    LivenessGesture.turnRight => 'Turn Right',
    LivenessGesture.nod => 'Nod',
  };

  @override
  String gestureInstruction(LivenessGesture gesture) => switch (gesture) {
    LivenessGesture.blink => 'Blink your eyes clearly a few times',
    LivenessGesture.mouthOpen => 'Open your mouth wide for 2 seconds',
    LivenessGesture.headShake => 'Slowly shake your head from side to side',
    LivenessGesture.smile => 'Smile widely and hold for 2 seconds',
    LivenessGesture.turnLeft => 'Turn your head to the left and hold',
    LivenessGesture.turnRight => 'Turn your head to the right and hold',
    LivenessGesture.nod => 'Slowly nod your head down and up',
  };

  @override
  String hintTitle(LivenessCaptureHint hint) => switch (hint) {
    LivenessCaptureHint.noFace => 'Face Not Detected',
    LivenessCaptureHint.moveCloser => 'Move Closer',
    LivenessCaptureHint.moveBack => 'Move Back',
    LivenessCaptureHint.centerFace => 'Center Your Face',
    LivenessCaptureHint.lookLevel => 'Hold Phone at Eye Level',
    LivenessCaptureHint.faceStraight => 'Look Straight Ahead',
    LivenessCaptureHint.tooDark => 'Too Dark',
    LivenessCaptureHint.tooBright => 'Too Bright',
    LivenessCaptureHint.holdStill => 'Hold Still',
    LivenessCaptureHint.multipleFaces => 'One Face Only',
  };

  @override
  String hintInstruction(LivenessCaptureHint hint) => switch (hint) {
    LivenessCaptureHint.noFace =>
      'Bring your face into the circle and look at the camera',
    LivenessCaptureHint.moveCloser =>
      'Move your face a little closer to the camera',
    LivenessCaptureHint.moveBack => 'Hold the phone a little further away',
    LivenessCaptureHint.centerFace =>
      'Line your face up with the middle of the circle',
    LivenessCaptureHint.lookLevel =>
      'Raise the phone so the camera is level with your eyes',
    LivenessCaptureHint.faceStraight =>
      'Face the camera straight on, without turning your head',
    LivenessCaptureHint.tooDark =>
      'Move somewhere brighter or face a light source',
    LivenessCaptureHint.tooBright => 'Move away from strong direct light',
    LivenessCaptureHint.holdStill =>
      'Hold still and look directly at the camera',
    LivenessCaptureHint.multipleFaces =>
      'Make sure only your face is in the frame',
  };

  @override
  String error(LivenessErrorKind kind) => switch (kind) {
    LivenessErrorKind.noCamera => 'No camera available',
    LivenessErrorKind.cameraFailed => 'Could not start the camera',
  };
}
