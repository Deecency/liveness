import 'package:liveness/shared/l10n/liveness_localizations_en.dart';
import 'package:material_ui/material_ui.dart';

/// Enum for liveness result status
enum LivenessResultStatus { success, failed, timeout, cancelled }

/// Why a session stopped before the person could finish, as
/// `LivenessState.errorKind` reports it.
enum LivenessErrorKind {
  /// The phone has no camera the package can use.
  noCamera,

  /// The camera was found but would not start.
  cameraFailed,
}

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

/// The English copy for each capture hint. The screen shows the app's
/// language through `LivenessLocalizations`; these stay for apps that read
/// them directly.
extension LivenessCaptureHintExtension on LivenessCaptureHint {
  String get title => const LivenessLocalizationsEn().hintTitle(this);

  String get instruction =>
      const LivenessLocalizationsEn().hintInstruction(this);
}

/// Extension to get gesture properties
extension LivenessGestureExtension on LivenessGesture {
  /// The English name. The screen uses `LivenessLocalizations.gestureName`.
  String get displayName => const LivenessLocalizationsEn().gestureName(this);

  /// The English instruction. The screen uses
  /// `LivenessLocalizations.gestureInstruction`.
  String get instruction =>
      const LivenessLocalizationsEn().gestureInstruction(this);

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
