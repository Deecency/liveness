import 'package:flutter/material.dart';
import 'package:liveness/shared/shared.dart';
import 'package:liveness/src/liveness_controller.dart';

/// The ready-made liveness screen: the package's own look, drawn over a
/// [LivenessController]. An app that wants its own design uses
/// [LivenessController] and `LivenessPreview` instead.
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

class _FaceLivenessState extends State<FaceLiveness> {
  late final LivenessController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LivenessController(config: widget.config);
    _controller.initialize();
    _controller.start();
    _controller.result.then((result) {
      // Popped some other way first (system back): nothing to report.
      if (!mounted) return;
      widget.onResult(result);
      // Auto close page after callback
      Navigator.of(context).pop(result);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCancel() {
    widget.onCancel?.call();
    _controller.cancel();
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
          child: ValueListenableBuilder<LivenessState>(
            valueListenable: _controller,
            builder: (context, state, _) => _body(theme, state),
          ),
        ),
      ),
    );
  }

  // The last state before the session finished. The page closes itself as
  // soon as the result is in, so for that last frame it keeps showing what
  // it showed, as it always has.
  LivenessState? _lastLive;

  Widget _body(LivenessTheme theme, LivenessState current) {
    final state = current.phase == LivenessPhase.finished
        ? (_lastLive ?? current)
        : (_lastLive = current);
    // The capture guide stays up while the photo is being taken.
    final capturing =
        state.phase == LivenessPhase.finalCapture ||
        state.phase == LivenessPhase.completing;
    final error = current.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          const SizedBox(height: 8),
          CameraPreviewWidget(
            config: widget.config,
            controller: cameraOf(_controller),
            timeRemaining: state.timeRemaining,
            isInitialised: state.cameraReady,
            showFaceGuide: capturing,
            faceGuideAligned: capturing && state.hint == null,
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
              capturing: capturing,
              completing: state.phase == LivenessPhase.completing,
              currentStep: state.currentGesture,
              waiting: state.phase == LivenessPhase.preparing,
              captureHint: state.hint,
            ),
          ),
          if (widget.config.showTimer) ...[
            const SizedBox(height: 24),
            ProgressTimer(
              config: widget.config,
              timeRemaining: state.timeRemaining,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            _buildErrorMessage(error),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage(String message) {
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
