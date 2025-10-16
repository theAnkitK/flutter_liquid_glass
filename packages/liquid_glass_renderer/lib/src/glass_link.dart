import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_link_scope.dart';

/// A link that connects liquid glass shapes to their parent layer for
/// efficient communication of position, size, and transform changes.
///
/// This replaces the ticker-based approach with an event-driven system
/// similar to follow_the_leader's LeaderLink pattern.
@internal
class GlassLink with ChangeNotifier {
  /// Creates a new [GlassLink].
  GlassLink();

  static GlassLink of(BuildContext context) {
    return LiquidGlassLinkScope.of(context).link;
  }

  /// Information about a shape registered with this link.
  final Map<LiquidGlassBlendGroup, Map<RenderLiquidGlass, GlassShapeInfo>>
      _shapes = {};

  /// Register a shape with this link.
  void registerShape(
    LiquidGlassBlendGroup blendGroup,
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes.putIfAbsent(
      blendGroup,
      () => {},
    )[renderObject] = GlassShapeInfo(
      shape: shape,
      glassContainsChild: glassContainsChild,
      blendGroup: blendGroup,
    );

    _notifyChange();
  }

  /// Unregister a shape from this link.
  void unregisterShape(
    LiquidGlassBlendGroup blendGroup,
    RenderObject renderObject,
  ) {
    _shapes[blendGroup]?.remove(renderObject);
    _notifyChange();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    LiquidGlassBlendGroup blendGroup,
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
    LiquidGlassBlendGroup? oldBlendGroup,
  }) {
    if (oldBlendGroup != null && oldBlendGroup != blendGroup) {
      // Move shape to new blend group
      final info = _shapes[oldBlendGroup]?.remove(renderObject);
      if (info != null) {
        _shapes.putIfAbsent(blendGroup, () => {})[renderObject] = info;
      }
    }

    _shapes[blendGroup]![renderObject]!
      ..shape = shape
      ..blendGroup = blendGroup
      ..glassContainsChild = glassContainsChild;

    _notifyChange();
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(
    LiquidGlassBlendGroup blendGroup,
    RenderLiquidGlass renderObject,
  ) {
    if (_shapes[blendGroup]?.containsKey(renderObject) ?? false) {
      _notifyChange();
    }
  }

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  /// Get the number of registered shapes.
  int get shapeCount => _shapes.length;

  bool _postFrameCallbackScheduled = false;

  void _notifyChange() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // We're in the middle of a layout and paint phase. Notify listeners
      // at the end of the frame.
      if (!_postFrameCallbackScheduled) {
        _postFrameCallbackScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameCallbackScheduled = false;
          if (hasListeners) notifyListeners();
        });
      }
      return;
    }

    // We're not in a layout/paint phase. Immediately notify listeners.
    notifyListeners();
  }

  @override
  void dispose() {
    _shapes.clear();
    super.dispose();
  }
}

/// Information about a shape stored in the [GlassLink].
class GlassShapeInfo {
  /// Creates a new [GlassShapeInfo].
  GlassShapeInfo({
    required this.shape,
    required this.glassContainsChild,
    required this.blendGroup,
  });

  /// The liquid shape.
  LiquidShape shape;

  /// The blend group this shape belongs to.
  LiquidGlassBlendGroup blendGroup;

  /// Whether the glass contains the child.
  bool glassContainsChild;
}
