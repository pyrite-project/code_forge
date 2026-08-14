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
            child: SizedBox(
              width: layoutInfo.childSize.width,
              height: layoutInfo.childSize.height,
              child: _OverflowHitTestStack(children: [widget.overlayChild]),
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
