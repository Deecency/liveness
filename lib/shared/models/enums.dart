import 'package:flutter/material.dart';

/// Enum for liveness result status
enum LivenessResultStatus { success, failed, timeout, cancelled }

/// Enum for different liveness gestures
enum LivenessGesture {
  blink,
  mouthOpen,
  headShake,
  smile,
  turnLeft,
  turnRight,

  /// Head down then up (or up then down), like a nod.
  nod,
}

/// What (if anything) the user needs to change during the final "hold still"
/// capture step for the frame to be usable by the downstream face match.
/// A `null` hint (see call sites) means the frame is good and the capture is
/// converging.
enum LivenessCaptureHint {
  noFace,
  moveCloser,
  moveBack,
  centerFace,
  lookLevel,
  faceStraight,
  tooDark,
  tooBright,
  holdStill,

  /// More than one face is in the frame. Raised only when
  /// `LivenessConfig.rejectMultipleFaces` is on.
  multipleFaces,
}

/// User-facing copy for each capture hint.
extension LivenessCaptureHintExtension on LivenessCaptureHint {
  String get title {
    switch (this) {
      case LivenessCaptureHint.noFace:
        return 'Face Not Detected';
      case LivenessCaptureHint.moveCloser:
        return 'Move Closer';
      case LivenessCaptureHint.moveBack:
        return 'Move Back';
      case LivenessCaptureHint.centerFace:
        return 'Center Your Face';
      case LivenessCaptureHint.lookLevel:
        return 'Hold Phone at Eye Level';
      case LivenessCaptureHint.faceStraight:
        return 'Look Straight Ahead';
      case LivenessCaptureHint.tooDark:
        return 'Too Dark';
      case LivenessCaptureHint.tooBright:
        return 'Too Bright';
      case LivenessCaptureHint.holdStill:
        return 'Hold Still';
      case LivenessCaptureHint.multipleFaces:
        return 'One Face Only';
    }
  }

  String get instruction {
    switch (this) {
      case LivenessCaptureHint.noFace:
        return 'Bring your face into the circle and look at the camera';
      case LivenessCaptureHint.moveCloser:
        return 'Move your face a little closer to the camera';
      case LivenessCaptureHint.moveBack:
        return 'Hold the phone a little further away';
      case LivenessCaptureHint.centerFace:
        return 'Line your face up with the middle of the circle';
      case LivenessCaptureHint.lookLevel:
        return 'Raise the phone so the camera is level with your eyes';
      case LivenessCaptureHint.faceStraight:
        return 'Face the camera straight on, without turning your head';
      case LivenessCaptureHint.tooDark:
        return 'Move somewhere brighter or face a light source';
      case LivenessCaptureHint.tooBright:
        return 'Move away from strong direct light';
      case LivenessCaptureHint.holdStill:
        return 'Hold still and look directly at the camera';
      case LivenessCaptureHint.multipleFaces:
        return 'Make sure only your face is in the frame';
    }
  }
}

/// Extension to get gesture properties
extension LivenessGestureExtension on LivenessGesture {
  String get displayName {
    switch (this) {
      case LivenessGesture.blink:
        return 'Blink';
      case LivenessGesture.mouthOpen:
        return 'Open Mouth';
      case LivenessGesture.headShake:
        return 'Shake Head';
      case LivenessGesture.smile:
        return 'Smile';
      case LivenessGesture.turnLeft:
        return 'Turn Left';
      case LivenessGesture.turnRight:
        return 'Turn Right';
      case LivenessGesture.nod:
        return 'Nod';
    }
  }

  String get instruction {
    switch (this) {
      case LivenessGesture.blink:
        return 'Blink your eyes clearly a few times';
      case LivenessGesture.mouthOpen:
        return 'Open your mouth wide for 2 seconds';
      case LivenessGesture.headShake:
        return 'Slowly shake your head from side to side';
      case LivenessGesture.smile:
        return 'Smile widely and hold for 2 seconds';
      case LivenessGesture.turnLeft:
        return 'Turn your head to the left and hold';
      case LivenessGesture.turnRight:
        return 'Turn your head to the right and hold';
      case LivenessGesture.nod:
        return 'Slowly nod your head down and up';
    }
  }

  IconData get icon {
    switch (this) {
      case LivenessGesture.blink:
        return Icons.visibility;
      case LivenessGesture.mouthOpen:
        return Icons.record_voice_over;
      case LivenessGesture.headShake:
        return Icons.swap_horiz;
      case LivenessGesture.smile:
        return Icons.sentiment_very_satisfied;
      case LivenessGesture.turnLeft:
        return Icons.keyboard_arrow_left;
      case LivenessGesture.turnRight:
        return Icons.keyboard_arrow_right;
      case LivenessGesture.nod:
        return Icons.swap_vert;
    }
  }
}
