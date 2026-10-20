import 'package:liveness/shared/models/enums.dart';
import 'package:liveness/shared/models/result.dart';

/// Where a liveness session is, as `LivenessController` reports it.
enum LivenessPhase {
  /// The short "get ready" wait before the first gesture is asked for.
  preparing,

  /// Asking for [LivenessState.currentGesture].
  gesture,

  /// Every gesture is done; waiting for a steady, well-framed, well-lit,
  /// straight-on face before the photo is taken. [LivenessState.hint] says
  /// what to fix, or is null when the frame is good.
  finalCapture,

  /// Taking the final photo.
  completing,

  /// Over: [LivenessState.result] holds the outcome.
  finished,
}

/// One immutable snapshot of a liveness session, for an app that draws its
/// own camera screen. A new one is published whenever anything in it
/// changes.
class LivenessState {
  const LivenessState({
    required this.phase,
    required this.cameraReady,
    required this.gestures,
    required this.currentIndex,
    required this.completed,
    required this.faceCount,
    required this.timeRemaining,
    required this.timeoutSeconds,
    this.currentGesture,
    this.gestureProgress = 0,
    this.hint,
    this.error,
    this.result,
  });

  /// Where the session is.
  final LivenessPhase phase;

  /// Whether the camera is running. Show a placeholder until it is.
  final bool cameraReady;

  /// The gestures this session asks for, in order (a random pick when
  /// `LivenessConfig.randomGestureCount` is set).
  final List<LivenessGesture> gestures;

  /// The index into [gestures] of the one being asked for (the last one
  /// once they're all done).
  final int currentIndex;

  /// The gesture being asked for; null outside [LivenessPhase.gesture].
  final LivenessGesture? currentGesture;

  /// How far into [currentGesture] the person is, from 0 to 1: how far the
  /// head has turned toward the turn angle, how many of the required smile
  /// or open-mouth frames are held, how many blinks are done, how many sides
  /// of a shake or nod are reached. It can fall back (a smile that slips, a
  /// head that turns back); the gesture counts once it's done, and the next
  /// one starts at 0.
  final double gestureProgress;

  /// The gestures done so far.
  final Set<LivenessGesture> completed;

  /// During [LivenessPhase.preparing] and [LivenessPhase.finalCapture]:
  /// what the person needs to fix (no face, move closer, centre, light...),
  /// or null when the frame is good. Null during the gestures.
  final LivenessCaptureHint? hint;

  /// Faces in the last frame looked at: 0 means no face is in view, more
  /// than 1 means someone else is in the frame.
  final int faceCount;

  /// Seconds left before the session times out. Resets after each gesture.
  final int timeRemaining;

  /// The full countdown, for drawing progress against [timeRemaining].
  final int timeoutSeconds;

  /// What went wrong (the camera failed to start), when something did. The
  /// session then finishes as failed a few seconds later.
  final String? error;

  /// The outcome, once [phase] is [LivenessPhase.finished].
  final LivenessResult? result;

  /// Whether a face is in view.
  bool get faceDetected => faceCount > 0;

  /// Whether [gesture] is done.
  bool isCompleted(LivenessGesture gesture) => completed.contains(gesture);
}
