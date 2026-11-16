import 'dart:ui';

import 'package:liveness/shared/l10n/liveness_localizations.dart';
import 'package:liveness/shared/models/enums.dart';
import 'package:liveness/shared/models/liveness_thresholds.dart';
import 'package:liveness/shared/theme.dart';

/// Configuration class for liveness detection
class LivenessConfig {
  /// The app bar title. Null shows `LivenessLocalizations.title` in the
  /// app's language.
  final String? title;

  /// The screen's words. Null uses the built-in English or French,
  /// whichever matches the app's locale; set it for other wording or
  /// another language.
  final LivenessLocalizations? localizations;

  final int timeoutSeconds;

  /// The gestures to run, in order — or, when [randomGestureCount] is set, the
  /// pool to draw a random challenge from.
  final List<LivenessGesture> requiredGestures;

  /// When non-null, [requiredGestures] is treated as a pool and this many
  /// distinct gestures are picked from it at random (in random order) each
  /// time the flow starts. Clamped to the pool size. Null ⇒ run
  /// [requiredGestures] as given.
  final int? randomGestureCount;

  final Color primaryColor;
  final Color successColor;
  final Color errorColor;
  final bool showInstructions;
  final bool showTimer;
  final LivenessTheme theme;

  /// Optional overrides for the per-step detection thresholds, and the
  /// runtime auto-adjust settings. Defaults to all-package-defaults with
  /// auto-adjust enabled.
  final LivenessThresholds thresholds;

  /// When true, a frame with more than one face counts for nothing: no
  /// gesture progress, no final photo, and the capture hint becomes
  /// [LivenessCaptureHint.multipleFaces]. Off by default, which keeps the
  /// original behaviour (the first face found is used).
  final bool rejectMultipleFaces;

  const LivenessConfig({
    this.title,
    this.localizations,
    this.timeoutSeconds = 30,
    this.requiredGestures = const [
      LivenessGesture.mouthOpen,
      LivenessGesture.headShake,
      LivenessGesture.blink,
    ],
    this.randomGestureCount,
    this.primaryColor = const Color(0xFF2196F3),
    this.successColor = const Color(0xFF4CAF50),
    this.errorColor = const Color(0xFFF44336),
    this.showInstructions = true,
    this.showTimer = true,
    this.theme = const LivenessTheme(),
    this.thresholds = const LivenessThresholds(),
    this.rejectMultipleFaces = false,
  });
}
