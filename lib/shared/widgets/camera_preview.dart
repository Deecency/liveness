import 'package:camera/camera.dart';
import 'package:liveness/shared/l10n/liveness_localizations.dart';
import 'package:liveness/shared/models/config.dart';
import 'package:liveness/shared/theme.dart';
import 'package:material_ui/material_ui.dart';

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({
    super.key,

    required this.config,
    required this.timeRemaining,
    this.isInitialised = false,
    this.controller,
    this.showFaceGuide = false,
    this.faceGuideAligned = false,
  });

  final LivenessConfig config;
  final num timeRemaining;
  final bool isInitialised;
  final CameraController? controller;

  /// Draws an oval face-alignment guide over the preview. Shown only during
  /// the final capture hold (turning gestures earlier would fight it).
  final bool showFaceGuide;

  /// When true the guide is drawn in the success colour — the current frame
  /// is well framed/lit/level and the capture is converging.
  final bool faceGuideAligned;

  bool get initialised => !isInitialised || controller == null;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    final progress = config.timeoutSeconds == 0
        ? 0.0
        : (timeRemaining / config.timeoutSeconds).clamp(0.0, 1.0);

    final ringColor = timeRemaining <= 10
        ? config.errorColor
        : config.primaryColor;
    return SizedBox(
      height: theme.ringSize,
      width: theme.ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated progress ring
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, _) => CustomPaint(
              size: Size(theme.ringSize, theme.ringSize),
              painter: _RingPainter(
                progress: value,
                color: ringColor,
                trackColor: ringColor.withValues(alpha: 0.12),
                strokeWidth: theme.ringThickness,
              ),
            ),
          ),
          // Camera circle
          Container(
            height: theme.ringSize - theme.ringThickness * 4,
            width: theme.ringSize - theme.ringThickness * 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.surfaceColor,
              boxShadow: theme.cardShadow,
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  initialised
                      ? _buildCameraLoading(context, theme)
                      : OverflowBox(
                          maxWidth: double.infinity,
                          maxHeight: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: controller!.value.previewSize!.height,
                              height: controller!.value.previewSize!.width,
                              child: CameraPreview(controller!),
                            ),
                          ),
                        ),
                  if (showFaceGuide && !initialised)
                    CustomPaint(
                      painter: _FaceGuidePainter(
                        color: faceGuideAligned
                            ? config.successColor
                            : Colors.white,
                        aligned: faceGuideAligned,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraLoading(BuildContext context, LivenessTheme theme) {
    return Container(
      color: theme.surfaceColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(config.primaryColor),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            LivenessLocalizations.of(context, config).initializingCamera,
            style: TextStyle(
              fontSize: 13,
              color: theme.mutedTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    const startAngle = -3.14159 / 2; // top
    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// A head-and-shoulders oval drawn slightly above the preview's centre, so a
/// user lining their face up with it naturally raises the phone to eye level.
class _FaceGuidePainter extends CustomPainter {
  final Color color;
  final bool aligned;

  _FaceGuidePainter({required this.color, required this.aligned});

  @override
  void paint(Canvas canvas, Size size) {
    // Oval a bit taller than wide, centred horizontally and lifted so its
    // middle sits above the frame centre (eye line, not chin line).
    final ovalWidth = size.width * 0.58;
    final ovalHeight = size.height * 0.78;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: ovalWidth,
      height: ovalHeight,
    );

    // Dim everything outside the oval so the target area reads clearly.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: aligned ? 0.18 : 0.32),
    );

    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3.5 : 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.aligned != aligned;
}
