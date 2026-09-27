import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class CodeForgeRootOverlayGeometry extends InheritedWidget {
  const CodeForgeRootOverlayGeometry({
    super.key,
    required this.targetOrigin,
    required this.overlaySize,
    required super.child,
  });

  final Offset targetOrigin;
  final Size overlaySize;

  Rect get overlayBoundsInTarget => Rect.fromLTWH(
    -targetOrigin.dx,
    -targetOrigin.dy,
    overlaySize.width,
    overlaySize.height,
  );

  static CodeForgeRootOverlayGeometry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CodeForgeRootOverlayGeometry>();
  }

  @override
  bool updateShouldNotify(CodeForgeRootOverlayGeometry oldWidget) {
    return targetOrigin != oldWidget.targetOrigin ||
        overlaySize != oldWidget.overlaySize;
  }
}

extension CodeForgeRootOverlayWidget on Widget {
  Widget inCodeForgeRootOverlay({required Size targetSize}) {
    return CodeForgeRootOverlayPortal(
      targetSize: targetSize,
      overlayChild: this,
    );
  }
}

/// Hosts an editor popup in the root overlay while retaining local coordinates.
///
/// This is an internal CodeForge widget and is intentionally not exported from
/// the package entrypoint.
class CodeForgeRootOverlayPortal extends StatefulWidget {
  const CodeForgeRootOverlayPortal({
    super.key,
    required this.targetSize,
    required this.overlayChild,
  });

  final Size targetSize;
  final Widget overlayChild;

  @override
  State<CodeForgeRootOverlayPortal> createState() =>
      _CodeForgeRootOverlayPortalState();
}

class _CodeForgeRootOverlayPortalState
    extends State<CodeForgeRootOverlayPortal> {
  final OverlayPortalController _controller = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, layoutInfo) {
        final targetOrigin = MatrixUtils.transformPoint(
          layoutInfo.childPaintTransform,
          Offset.zero,
        );
        return CodeForgeRootOverlayGeometry(
          targetOrigin: targetOrigin,
          overlaySize: layoutInfo.overlaySize,
          child: Transform(
            transform: layoutInfo.childPaintTransform,
            alignment: Alignment.topLeft,
            // The overlay child is laid out in the *target's* coordinate space,
            // so its box has to be the target's size — here the editor
            // viewport handed in as [CodeForgeRootOverlayPortal.targetSize].
            //
            // Using `layoutInfo.childSize` instead sized this box to the whole
            // root overlay. That is invisible to `Positioned(top: ..)` (which
            // measures from the top of the box) but shifts every popup anchored
            // with `Positioned(bottom: ..)` down by the difference: the hover
            // popup is anchored with `bottom`, so it landed hundreds of pixels
            // below the word whenever it flipped above the cursor.
            //
            // `UnconstrainedBox` is what actually makes the width and height
            // here take effect. The overlay lays its children out with tight
            // constraints spanning the whole overlay, and a `SizedBox` under
            // tight constraints cannot shrink: it defers to the parent and
            // renders at the overlay's full size. That is precisely the bug
            // described above, so the box has to be laid out without a
            // constraint that would override the target size. It is positioned
            // back at the top left so dropping the constraints does not move
            // the child.
            child: UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: widget.targetSize.width,
                height: widget.targetSize.height,
                child: _OverflowHitTestStack(children: [widget.overlayChild]),
              ),
            ),
          ),
        );
      },
      child: SizedBox(
        width: widget.targetSize.width,
        height: widget.targetSize.height,
      ),
    );
  }
}

class _OverflowHitTestStack extends Stack {
  const _OverflowHitTestStack({required super.children})
    : super(alignment: Alignment.topLeft, clipBehavior: Clip.none);

  @override
  RenderStack createRenderObject(BuildContext context) {
    return _RenderOverflowHitTestStack(
      alignment: alignment,
      textDirection: textDirection,
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    renderObject
      ..alignment = alignment
      ..textDirection = textDirection
      ..fit = fit
      ..clipBehavior = clipBehavior;
  }
}

class _RenderOverflowHitTestStack extends RenderStack {
  _RenderOverflowHitTestStack({
    required super.alignment,
    required super.textDirection,
    required super.fit,
    required super.clipBehavior,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
