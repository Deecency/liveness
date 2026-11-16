import 'package:liveness/liveness.dart';
import 'package:material_ui/material_ui.dart';

class ProgressTimer extends StatelessWidget {
  const ProgressTimer({
    super.key,
    required this.timeRemaining,
    required this.config,
  });

  final num timeRemaining;
  final LivenessConfig config;

  @override
  Widget build(BuildContext context) {
    final danger = timeRemaining <= 10;
    final color = danger ? config.errorColor : config.successColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            LivenessLocalizations.of(
              context,
              config,
            ).secondsRemaining(timeRemaining),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
