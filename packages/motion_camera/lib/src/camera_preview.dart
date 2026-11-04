import 'package:flutter/widgets.dart';

import 'controller.dart';

/// The live image of a capture session started with `preview: true`.
///
/// One camera session feeds both this texture and the landmark stream, so a
/// mirror and its skeleton overlay never need a second camera. The image is
/// in the landmarks' space (un-mirrored, portrait); [mirror] flips the whole
/// stack — texture and [overlay] together — for a selfie-style mirror, so
/// the overlay stays aligned without remapping landmarks.
class MotionCameraPreview extends StatelessWidget {
  const MotionCameraPreview({
    required this.session,
    this.mirror = true,
    this.overlay,
    super.key,
  });

  final CameraSessionInfo session;
  final bool mirror;

  /// Painted on top of the image in the same coordinate box (normalized
  /// landmark x→width, y→height).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final int? id = session.previewTextureId;
    if (id == null) return const SizedBox.shrink();
    final Widget stack = AspectRatio(
      aspectRatio: session.width / session.height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RotatedBox(
            quarterTurns: session.previewQuarterTurns,
            child: Texture(textureId: id),
          ),
          ?overlay,
        ],
      ),
    );
    return mirror ? Transform.flip(flipX: true, child: stack) : stack;
  }
}
