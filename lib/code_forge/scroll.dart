import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A custom two-dimensional viewport for the code editor.
///
/// This viewport is used internally by [CodeForge] to enable both vertical
/// and horizontal scrolling within the editor. It delegates to a
/// [Render2DCodeField] for layout and painting.
class CustomViewport extends TwoDimensionalViewport {
  final bool lineWrap;

  /// Creates a [CustomViewport] with the required scroll offsets and axes.
  const CustomViewport({
    super.key,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required TwoDimensionalChildBuilderDelegate super.delegate,
    required super.mainAxis,
    required this.lineWrap,
  });

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) {
    return Render2DCodeField(
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalAxisDirection,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalAxisDirection,
      delegate: delegate,
      mainAxis: mainAxis,
      childManager: context as TwoDimensionalChildManager,
      lineWrap: lineWrap,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTwoDimensionalViewport renderObject,
  ) {
    (renderObject as Render2DCodeField).lineWrap = lineWrap;
    renderObject
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..delegate = delegate
      ..mainAxis = mainAxis;
  }
}

/// The render object for the code editor's two-dimensional viewport.
///
/// This class handles the layout of the code editor content and manages
/// the content dimensions for both vertical and horizontal scrolling.
class Render2DCodeField extends RenderTwoDimensionalViewport {
  bool lineWrap;

  /// Creates a [Render2DCodeField] with the required scroll configuration.
  Render2DCodeField({
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    required super.childManager,
    required this.lineWrap,
  });

  @override
  void layoutChildSequence() {
    final child = buildOrObtainChildFor(ChildVicinity(xIndex: 0, yIndex: 0));

    if (child != null) {
      child.layout(
        BoxConstraints(
          minHeight: 0,
          minWidth: 0,
          maxWidth: lineWrap ? viewportDimension.width : double.infinity,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      parentDataOf(child).layoutOffset = Offset.zero;

      verticalOffset.applyContentDimensions(
        0.0,
        math.max(0.0, child.size.height - viewportDimension.height),
      );
      horizontalOffset.applyContentDimensions(
        0.0,
        math.max(0.0, child.size.width - viewportDimension.width),
      );
    }
  }
}

class CustomScrollbar extends RawScrollbar {
  final BorderRadius borderRadius;

  const CustomScrollbar({
    super.key,
    required super.child,
    required super.controller,
    required this.borderRadius,
    super.thumbVisibility,
    super.interactive,
    super.thumbColor,
    super.thickness,
    super.crossAxisMargin,
    super.mainAxisMargin,
    super.scrollbarOrientation,
    super.trackBorderColor,
    super.fadeDuration,
    super.timeToFade,
    super.trackRadius,
    super.trackVisibility,
    super.minOverscrollLength,
    super.minThumbLength,
    super.padding,
    super.pressDuration,
    super.trackColor,
    super.notificationPredicate,
  });

  @override
  RawScrollbarState<RawScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends RawScrollbarState<CustomScrollbar> {
  @override
  void updateScrollbarPainter() {
    scrollbarPainter
      ..color = widget.thumbColor ?? Colors.grey.withAlpha(100)
      ..textDirection = Directionality.of(context)
      ..thickness = widget.thickness ?? 8.0
      ..shape = _CustomThumbBorder(borderRadius: widget.borderRadius);
  }
}

class _CustomThumbBorder extends RoundedRectangleBorder {
  const _CustomThumbBorder({required super.borderRadius})
    : super(side: BorderSide.none);

  @override
  bool operator ==(Object other) {
    return other is _CustomThumbBorder && other.borderRadius == borderRadius;
  }

  @override
  int get hashCode => borderRadius.hashCode;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));

  @override
  ShapeBorder scale(double t) => this;
}
