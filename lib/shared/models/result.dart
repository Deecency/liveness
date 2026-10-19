import 'dart:io';

import 'package:liveness/shared/models/enums.dart';

/// Result class for liveness detection
class LivenessResult {
  final LivenessResultStatus status;
  final String message;

  /// The single best (sharpest) captured still. Kept for backward
  /// compatibility; prefer [capturedImages] when doing a face match so the
  /// probe embedding can be averaged over frames.
  final File? capturedImage;

  /// Every still captured at the end of the flow, sharpest first. Empty on a
  /// non-success result. Usually 1–2 frames.
  final List<File> capturedImages;

  final List<LivenessGesture> completedGestures;
  final double confidence;
  final Duration duration;

  /// Per-gesture snapshot of where each adaptive threshold ended up, keyed by
  /// [LivenessGesture.name]. Each value holds `default`, `effective`,
  /// `relaxations` and (when known) `bestApproach`. For telemetry / tuning.
  final Map<String, Map<String, double>> thresholdAdjustments;

  const LivenessResult({
    required this.status,
    required this.message,
    this.capturedImage,
    this.capturedImages = const [],
    required this.completedGestures,
    required this.confidence,
    required this.duration,
    this.thresholdAdjustments = const {},
  });

  // Backward compatibility
  bool get success => status == LivenessResultStatus.success;
}
