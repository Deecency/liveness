import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:liveness/shared/shared.dart';

part 'face_liveness_input.dart';
part 'face_liveness_gestures.dart';
part 'face_liveness_capture.dart';
part 'face_liveness_thresholds.dart';

/// The camera, the face detection, the gesture challenge and the final
/// photo — everything a liveness check does except draw it.
///
/// [FaceLiveness] draws its own screen on top of this. An app that wants
/// its own design uses it directly:
///
/// ```dart
/// final controller = LivenessController(config: config);
/// await controller.initialize();
/// controller.start();
/// // Draw LivenessPreview(controller: controller) and rebuild from
/// // controller.value (a LivenessState) via ValueListenableBuilder.
/// final result = await controller.result;
/// controller.dispose();
/// ```
///
/// The logic is split across `part` files by concern:
///  - `face_liveness_input.dart`      — camera frame → ML Kit input, brightness
///  - `face_liveness_gestures.dart`   — per-gesture recognisers + progression
///  - `face_liveness_capture.dart`    — final "hold still" grading + still capture
///  - `face_liveness_thresholds.dart` — configurable + self-adjusting thresholds
class LivenessController extends ChangeNotifier
    implements ValueListenable<LivenessState> {
  /// Creates a controller for one liveness session.
  LivenessController({this.config = const LivenessConfig()})
    : _thr = _ResolvedThresholds(config.thresholds) {
    _gestures = _resolveGestures();
    _timeRemaining = config.timeoutSeconds;
    _state = _snapshot();
  }

  /// The session's settings.
  final LivenessConfig config;

  late LivenessState _state;
  final Completer<LivenessResult> _result = Completer<LivenessResult>();

  /// The session as it stands now.
  @override
  LivenessState get value => _state;

  /// The same as [value].
  LivenessState get state => _state;

  /// Completes once the session ends — success, failure, timeout or
  /// cancel — with the same [LivenessResult] [FaceLiveness] returns. Also
  /// completes (as cancelled) when the controller is disposed first.
  Future<LivenessResult> get result => _result.future;

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _initializeCalled = false;
  bool _started = false;
  bool _disposed = false;
  bool _isProcessing = false;
  Timer? _readyTimer;
  LivenessResult? _finalResult;

  bool get _finished => _finalResult != null;

  // True only once _completeSuccessfully is actually running (stopping the
  // stream and taking the final still photo) — distinct from _isInFinalCapture,
  // which covers the earlier "please hold still and face the camera" wait.
  bool _isCompleting = false;

  // Face detection. Contours are needed for real mouth-open detection (see
  // _detectMouthOpen); a single detector instance is reused for the life of
  // this controller and closed in dispose().
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // Liveness detection state
  int _currentGestureIndex = 0;
  final Set<LivenessGesture> _completedGestures = {};
  int _timeRemaining = 30;
  Timer? _timer;
  bool _livenessStarted = false;
  bool _isDetecting = false;
  DateTime _startTime = DateTime.now();
  String _errorMessage = '';
  int _faceCount = 0;

  // How far into the current gesture the person is, 0–1. See _setProgress.
  double _gestureProgress = 0;

  // Diagnostic-only frame counters — see _CameraInput._onCameraImage and
  // _CameraInput._inputImageFromCameraImage for why these silent branches
  // specifically needed visibility.
  int _nullInputImageFrames = 0;
  int _emptyFacesFrames = 0;
  int _formatMismatchFrames = 0;
  int _paddedBufferFrames = 0;
  bool _loggedFirstFrameBufferInfo = false;

  // Current step state
  LivenessGesture? _currentStep;
  bool _isWaitingToStart = true;
  bool _isInFinalCapture = false;
  bool _isFacingCamera = false;
  int _facingCameraFrames = 0;

  // Live guidance shown during the final capture hold. Null while the current
  // frame is good and the capture is converging (or before it starts).
  LivenessCaptureHint? _captureHint;

  // Clockwise degrees the live buffer is rotated to become upright, cached
  // from the last _inputImageFromCameraImage call so face bounding boxes
  // (reported by ML Kit in upright space) can be compared against the right
  // frame dimensions.
  int _lastRotationDegrees = 0;

  // Per-step detection thresholds (config-or-default). The gesture ones
  // adapt at runtime; see _trackApproach.
  final _ResolvedThresholds _thr;

  // Adaptation bookkeeping for the current step.
  DateTime _stepStartedAt = DateTime.now();
  DateTime? _lastAdaptAt;

  // Best value the user has reached toward passing this step, keyed by
  // threshold name (a step can involve more than one, e.g. blink).
  final Map<String, double> _stepBest = {};

  // What each completed gesture's threshold ended up at — surfaced on the
  // LivenessResult for telemetry / tuning.
  final Map<String, Map<String, double>> _thresholdAdjustments = {};

  // Gesture detection variables
  double? _previousLeftEyeOpenProbability;
  double? _previousRightEyeOpenProbability;
  int _headShakeDirection = 0; // -1 turned left, 0 neutral, 1 turned right
  int _headShakeReversals = 0;
  int _nodDirection = 0; // -1 down, 0 level, 1 up
  int _nodReversals = 0;
  int _blinkCount = 0;
  int _mouthOpenFrames = 0;
  int _smileFrames = 0;

  // Gesture completion tracking
  bool _blinkDetected = false;
  bool _mouthOpenDetected = false;
  bool _headShakeDetected = false;
  bool _smileDetected = false;
  bool _turnLeftDetected = false;
  bool _turnRightDetected = false;
  bool _nodDetected = false;

  File? _capturedImage;
  List<File> _capturedImages = const [];

  // The gestures actually run this session: config.requiredGestures as given,
  // or a random pick from it when config.randomGestureCount is set.
  late final List<LivenessGesture> _gestures;

  /// Applies [fn] and publishes a new [LivenessState]. Does nothing once
  /// disposed.
  void _update(VoidCallback fn) {
    if (_disposed) return;
    fn();
    _state = _snapshot();
    notifyListeners();
  }

  LivenessState _snapshot() => LivenessState(
    phase: _finished
        ? LivenessPhase.finished
        : _isCompleting
        ? LivenessPhase.completing
        : _isInFinalCapture
        ? LivenessPhase.finalCapture
        : _isWaitingToStart
        ? LivenessPhase.preparing
        : LivenessPhase.gesture,
    cameraReady: _cameraReady,
    gestures: _gestures,
    currentIndex: _currentGestureIndex,
    currentGesture: _currentStep,
    gestureProgress: _gestureProgress,
    completed: Set.unmodifiable(_completedGestures),
    hint: _captureHint,
    faceCount: _faceCount,
    timeRemaining: _timeRemaining,
    timeoutSeconds: config.timeoutSeconds,
    error: _errorMessage.isEmpty ? null : _errorMessage,
    result: _finalResult,
  );

  /// Opens the front camera. Call once, before or alongside [start]. A
  /// failure doesn't throw: it shows as [LivenessState.error], and the
  /// session finishes as failed a few seconds later.
  Future<void> initialize() async {
    if (_initializeCalled || _disposed) return;
    _initializeCalled = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No camera available');
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Request a single-plane pixel format directly usable by ML Kit
      // (nv21 on Android, bgra8888 on iOS) so incoming frames don't need to
      // be re-encoded before running face detection on them.
      //
      // ResolutionPreset.medium on both platforms. Every preset above it
      // switches the capture to a wider aspect ratio that the device
      // produces by cropping into the sensor's field of view (confirmed on
      // both iOS and Android) — the preview ends up noticeably "zoomed in"
      // and the user has to hold the phone too far from their face to fill
      // the framing circle. .medium keeps the full 4:3 FOV; sharpness is
      // handled instead by the focus/exposure lock, the sharpest-of-two
      // still, and the eye-level capture gate.
      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _cameraController = controller;

      await controller.initialize();

      if (_disposed) {
        // Disposed while the camera was opening: dispose() saw no camera
        // yet, so release it here.
        await controller.dispose();
        return;
      }
      _update(() => _cameraReady = true);
      _maybeStartLivenessDetection();
    } catch (e) {
      _showError('Failed to initialize camera: $e');
    }
  }

  /// Starts the session: the countdown, then after a short "get ready"
  /// pause the first gesture. Call once.
  void start() {
    if (_started || _disposed || _finished) return;
    _started = true;
    _startTime = DateTime.now();
    _timer = _createCountdownTimer();

    // Start liveness detection after a short delay
    _readyTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed || _finished) return;
      _update(() {
        _isWaitingToStart = false;
        // The get-ready framing hint doesn't carry into the gestures.
        _captureHint = null;
        if (_gestures.isNotEmpty) {
          _currentStep = _gestures[0];
        }
      });
      _beginStepTracking();
      _maybeStartLivenessDetection();
    });
    _maybeStartLivenessDetection();
  }

  /// Ends the session as cancelled.
  void cancel() {
    if (_finished || _disposed) return;
    _timer?.cancel();
    _stopImageStream();
    _finish(
      LivenessResult(
        status: LivenessResultStatus.cancelled,
        message: 'Verification cancelled by user',
        capturedImage: null,
        completedGestures: _completedGestures.toList(),
        confidence: 0.0,
        duration: DateTime.now().difference(_startTime),
      ),
    );
  }

  /// Releases the camera and the face detector. An unfinished session
  /// completes [result] as cancelled.
  @override
  void dispose() {
    if (_disposed) return;
    if (!_result.isCompleted) {
      _result.complete(
        LivenessResult(
          status: LivenessResultStatus.cancelled,
          message: 'Verification cancelled by user',
          completedGestures: _completedGestures.toList(),
          confidence: 0.0,
          duration: DateTime.now().difference(_startTime),
        ),
      );
    }
    _disposed = true;
    _timer?.cancel();
    _readyTimer?.cancel();
    _stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  /// Stops the camera's live frame stream, if it's running. Safe to call
  /// even if streaming was never started.
  void _stopImageStream() {
    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      // Fire-and-forget: by the time this is called the session is
      // ending, so there's nothing to usefully await this against.
      controller.stopImageStream().catchError((_) {});
    }
  }

  /// One-second countdown ticker, restarted after each gesture.
  Timer _createCountdownTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || _finished) {
        timer.cancel();
        return;
      }
      if (_timeRemaining > 0) {
        _update(() => _timeRemaining--);
      } else {
        _onTimeout();
      }
    });
  }

  /// Starts the live frame stream once the session has started and the
  /// camera is ready — whichever happens last. Frames during the "get
  /// ready" pause only count faces and judge framing; no gesture is
  /// scored until it ends. Safe to call from anywhere; only starts once.
  void _maybeStartLivenessDetection() {
    if (_livenessStarted || !_started || _disposed || _finished) {
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _livenessStarted = true;
    controller.startImageStream(_onCameraImage);
  }

  /// Publishes [result] and completes [result]. Shared tail of every
  /// terminal state (success/timeout/failure/cancel); only the first wins.
  void _finish(LivenessResult result) {
    if (_finished || _result.isCompleted) return;
    _timer?.cancel();
    _readyTimer?.cancel();
    _update(() => _finalResult = result);
    _result.complete(result);
  }

  void _onTimeout() {
    _timer?.cancel();
    _stopImageStream();

    _finish(
      LivenessResult(
        status: LivenessResultStatus.timeout,
        message: 'Verification timed out',
        capturedImage: null,
        completedGestures: _completedGestures.toList(),
        confidence: 0.0,
        duration: DateTime.now().difference(_startTime),
      ),
    );
  }

  void _onFailure(String errorMessage) {
    _timer?.cancel();
    _stopImageStream();

    _finish(
      LivenessResult(
        status: LivenessResultStatus.failed,
        message: errorMessage,
        capturedImage: null,
        completedGestures: _completedGestures.toList(),
        confidence: 0.0,
        duration: DateTime.now().difference(_startTime),
      ),
    );
  }

  void _resetTimer() {
    _timer?.cancel();
    _update(() => _timeRemaining = config.timeoutSeconds);
    _timer = _createCountdownTimer();
  }

  void _showError(String message) {
    _update(() => _errorMessage = message);

    Timer(const Duration(seconds: 3), () {
      if (!_disposed) _onFailure(message);
    });
  }
}

/// The camera behind [controller], for `LivenessPreview`. Not exported:
/// apps draw the preview through `LivenessPreview`, never the camera
/// plugin directly.
CameraController? cameraOf(LivenessController controller) =>
    controller._cameraController;
