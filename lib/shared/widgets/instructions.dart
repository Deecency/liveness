import 'package:animate_do/animate_do.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:liveness/shared/models/config.dart';
import 'package:liveness/shared/models/enums.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
// isCompleting isInFinalCapture

class LivenessInstructionWidget extends StatelessWidget {
  const LivenessInstructionWidget({
    super.key,
    required this.config,
    this.waiting = true,
    this.completing = false,
    this.capturing = false,
    this.currentStep,
    this.captureHint,
  });

  final LivenessConfig config;
  final bool waiting;
  final bool completing;
  final bool capturing;
  final LivenessGesture? currentStep;

  /// During the final capture hold: what the user needs to fix, or null when
  /// the frame is good and the capture is converging.
  final LivenessCaptureHint? captureHint;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    _StepContent? content;

    if (waiting) {
      content = _StepContent(
        icon: CupertinoIcons.hourglass,
        color: config.theme.titleColor,
        title: 'Preparing Verification',
        subtitle:
            'Liveness verification will start automatically in a few seconds…',
        pulse: false,
      );
    } else if (completing) {
      content = _StepContent(
        icon: Icons.check_circle_rounded,
        color: config.successColor,
        title: 'Verification Successful!',
        subtitle: 'All gestures verified. Processing your result…',
        pulse: false,
      );
    } else if (currentStep != null) {
      content = _StepContent(
        icon: currentStep!.icon,
        color: config.primaryColor,
        title: currentStep!.displayName,
        subtitle: currentStep!.instruction,
        pulse: true,
      );
    } else if (capturing) {
      final converging = captureHint == null;
      final hint = captureHint ?? LivenessCaptureHint.holdStill;
      content = _StepContent(
        icon: converging
            ? Icons.check_circle_outline_rounded
            : Icons.filter_center_focus_rounded,
        color: converging ? config.successColor : config.primaryColor,
        title: hint.title,
        subtitle: hint.instruction,
        pulse: !converging,
      );
    }

    if (content == null) return const SizedBox.shrink(key: ValueKey('empty'));

    return Container(
      key: ValueKey(content.title),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.glassmorphism
            ? theme.surfaceColor
            : content.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: Border.all(
          color: theme.glassmorphism
              ? Colors.white.withValues(alpha: 0.24)
              : content.color.withValues(alpha: 0.2),
        ),
        boxShadow: theme.glassmorphism ? [] : theme.cardShadow,
      ),
      child: Column(
        children: [
          switch (currentStep) {
            null => ScaleTransition(
              scale: const AlwaysStoppedAnimation(1.0),
              child: CircularProgressIndicator(
                backgroundColor: Colors.grey.shade300,
                color: config.successColor,
                strokeCap: StrokeCap.round,
              ),
            ),
            _ => Pulse(
              infinite: true,
              curve: Curves.easeInOut,
              to: 1.2,
              loopDelay: Duration(milliseconds: 800),
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Lottie.asset(
                  'packages/${switch (currentStep) {
                    LivenessGesture.blink => 'liveness/assets/blink.json',
                    LivenessGesture.smile => 'liveness/assets/smile.json',
                    LivenessGesture.turnLeft => 'liveness/assets/turn_left.json',
                    LivenessGesture.turnRight => 'liveness/assets/turn_right.json',
                    LivenessGesture.mouthOpen => 'liveness/assets/mouth.json',
                    LivenessGesture.nod => 'liveness/assets/nod.json',
                    _ => 'liveness/assets/shake.json',
                  }}',
                  height: 80,
                ),
              ),
            ),
          },
          const SizedBox(height: 18),
          Text(
            content.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.glassmorphism ? theme.titleColor : content.color,
              fontFamily: theme.fontFamily,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            content.subtitle,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: theme.glassmorphism
                  ? theme.mutedTextColor
                  : content.color.withValues(alpha: 0.85),
              fontFamily: theme.fontFamily,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StepContent {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool pulse;

  _StepContent({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.pulse,
  });
}
