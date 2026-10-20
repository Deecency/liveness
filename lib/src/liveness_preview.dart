import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:liveness/src/liveness_controller.dart';

/// The live front-camera picture of a [LivenessController], with nothing
/// drawn on it, filling whatever space it's given (cropped to cover, never
/// letterboxed). It's the same picture [FaceLiveness] shows, so an app
/// draws its own mask, guide and wording around it without depending on
/// the camera plugin.
///
/// Shows [placeholder] (black by default) until the camera is ready.
class LivenessPreview extends StatelessWidget {
  /// Creates a preview of [controller]'s camera.
  const LivenessPreview({
    super.key,
    required this.controller,
    this.placeholder,
  });

  /// The session whose camera is shown.
  final LivenessController controller;

  /// Shown while the camera is starting.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final camera = cameraOf(controller);
        final size = camera?.value.previewSize;
        if (!controller.value.cameraReady || camera == null || size == null) {
          return placeholder ?? const ColoredBox(color: Colors.black);
        }
        // previewSize is reported landscape; the phone is held upright, so
        // its sides are swapped before covering the available space.
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.height,
                height: size.width,
                child: CameraPreview(camera),
              ),
            ),
          ),
        );
      },
    );
  }
}
