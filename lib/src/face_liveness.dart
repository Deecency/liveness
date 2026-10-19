import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:liveness/shared/shared.dart';

part 'face_liveness_input.dart';
part 'face_liveness_gestures.dart';
part 'face_liveness_capture.dart';
part 'face_liveness_thresholds.dart';

/// Standalone Liveness Detection Page.
///
/// The page state ([_FaceLivenessState]) is deliberately large and is split
/// across `part` files by concern:
///  - `face_liveness_input.dart`      — camera frame → ML Kit input, brightness
///  - `face_liveness_gestures.dart`   — per-gesture recognisers + progression
///  - `face_liveness_capture.dart`    — final "hold still" grading + still capture
///  - `face_liveness_thresholds.dart` — configurable + self-adjusting thresholds
///
/// This file keeps the widget, camera/timer lifecycle, terminal-state
/// reporting, and `build`.
class FaceLiveness extends StatefulWidget {
  final LivenessConfig config;
  final Function(LivenessResult) onResult;
  final VoidCallback? onCancel;

  const FaceLiveness({
    super.key,
    required this.onResult,
    this.config = const LivenessConfig(),
    this.onCancel,
  });

  /// Static method to easily navigate to liveness page
  static Future<LivenessResult?> show(
    BuildContext context, {
    LivenessConfig config = const LivenessConfig(),
    Function(LivenessResult)? onResult,
  }) async {
    // Note: the page always pops itself with the LivenessResult once it
    // reaches a terminal state (success/timeout/failure/cancel), so the
    // default `onResult` below must be a pure notification callback and
    // must NOT pop the navigator too, or the caller's own route gets
    // popped along with the liveness page.
    return await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(
        builder: (context) =>
            FaceLiveness(config: config, onResult: onResult ?? (_) {}),
      ),
    );
  }

  @override
  State<FaceLiveness> createState() => _FaceLivenessState();
}

class _FaceLivenessState extends State<FaceLiveness>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;

  // True only once _completeSuccessfully is actually running (stopping the
  // stream and taking the final still photo) — distinct from _isInFinalCapture,
  // which covers the earlier "please hold still and face the camera" wait.
  bool _isCompleting = false;

  // Face detection. Contours are needed for real mouth-open detection (see
  // _detectMouthOpen); a single detector instance is reused for the life of
  // this page and closed in _cleanup().
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
  DateTime? _startTime;
  String _errorMessage = '';

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

  // Per-step detection thresholds (config-or-default), resolved once in
  // initState. The gesture ones adapt at runtime; see _trackApproach.
  late final _ResolvedThresholds _thr;

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

  File? _capturedImage;
  List<File> _capturedImages = const [];

  // The gestures actually run this session: config.requiredGestures as given,
  // or a random pick from it when config.randomGestureCount is set.
  late final List<LivenessGesture> _gestures;

  late final AnimationController _pulseController;
  late final AnimationController _entranceController;

  /// Non-protected wrapper around [setState] so the `part`-file extensions
  /// (which are not instance members of this class) can request a rebuild
  /// without tripping `invalid_use_of_protected_member`.
  void _setState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();

    _thr = _ResolvedThresholds(widget.config.thresholds);
    _gestures = _resolveGestures();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _timeRemaining = widget.config.timeoutSeconds;
    _startTime = DateTime.now();

    _initializeCamera();
    _startTimer();

    // Start liveness detection after a short delay
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isWaitingToStart = false;
          if (_gestures.isNotEmpty) {
            _currentStep = _gestures[0];
          }
        });
        _beginStepTracking();
        _maybeStartLivenessDetection();
      }
    });
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    _pulseController.dispose();
    _entranceController.dispose();
    _timer?.cancel();
    _stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
  }

  /// Stops the camera's live frame stream, if it's running. Safe to call
  /// even if streaming was never started.
  void _stopImageStream() {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      // Fire-and-forget: by the time this is called we're already tearing
      // the page down, so there's nothing to usefully await this against.
      controller.stopImageStream().catchError((_) {});
    }
  }

  Future<void> _initializeCamera() async {
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
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _maybeStartLivenessDetection();
      }
    } catch (e) {
      _showError('Failed to initialize camera: $e');
    }
  }

  void _startTimer() {
    _timer = _createCountdownTimer();
  }

  /// One-second countdown ticker shared by [_startTimer] and [_resetTimer].
  Timer _createCountdownTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() {
          _timeRemaining--;
        });
      } else {
        _onTimeout();
      }
    });
  }

  /// Starts the live frame stream once both the initial "get ready" delay
  /// has elapsed and the camera has finished initializing — whichever
  /// happens last. Safe to call from either place; only starts once.
  void _maybeStartLivenessDetection() {
    if (_livenessStarted || _isWaitingToStart) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _livenessStarted = true;
    controller.startImageStream(_onCameraImage);
  }

  /// Reports [result] to the caller and closes the page. Shared tail of
  /// every terminal state (success/timeout/failure/cancel).
  void _finish(LivenessResult result) {
    widget.onResult(result);

    // Auto close page after callback
    if (mounted) {
      Navigator.of(context).pop(result);
    }
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
        duration: DateTime.now().difference(_startTime!),
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
        duration: DateTime.now().difference(_startTime!),
      ),
    );
  }

  void _onCancel() {
    _timer?.cancel();
    _stopImageStream();

    widget.onCancel?.call();
    _finish(
      LivenessResult(
        status: LivenessResultStatus.cancelled,
        message: 'Verification cancelled by user',
        capturedImage: null,
        completedGestures: _completedGestures.toList(),
        confidence: 0.0,
        duration: DateTime.now().difference(_startTime!),
      ),
    );
  }

  void _resetTimer() {
    // Cancel existing timer
    _timer?.cancel();

    // Reset time remaining to full timeout
    setState(() {
      _timeRemaining = widget.config.timeoutSeconds;
    });

    _timer = _createCountdownTimer();
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _onFailure(message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor ?? Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _CircleIconButton(
          icon: Icons.close_rounded,
          color: theme.titleColor,
          background: theme.surfaceColor,
          onTap: _onCancel,
        ),
        title: Text(
          widget.config.title,
          style: TextStyle(
            color: theme.titleColor,
            fontWeight: FontWeight.w600,
            fontFamily: theme.fontFamily,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: theme.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              children: [
                const SizedBox(height: 8),
                CameraPreviewWidget(
                  config: widget.config,
                  controller: _cameraController,
                  timeRemaining: _timeRemaining,
                  isInitialised: _isCameraInitialized,
                  showFaceGuide: _isInFinalCapture,
                  faceGuideAligned: _isInFinalCapture && _captureHint == null,
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: LivenessInstructionWidget(
                    config: widget.config,
                    capturing: _isInFinalCapture,
                    completing: _isCompleting,
                    currentStep: _currentStep,
                    waiting: _isWaitingToStart,
                    captureHint: _captureHint,
                  ),
                ),
                if (widget.config.showTimer) ...[
                  const SizedBox(height: 24),
                  ProgressTimer(
                    config: widget.config,
                    timeRemaining: _timeRemaining,
                  ),
                ],
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildErrorMessage(theme, _errorMessage),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(LivenessTheme theme, String message) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.config.errorColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.config.errorColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: widget.config.errorColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: widget.config.errorColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}
