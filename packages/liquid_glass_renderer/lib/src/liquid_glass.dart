// ignore_for_file: avoid_setters_without_getters

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_link_scope.dart';
import 'package:meta/meta.dart';

/// A liquid glass shape.
///
/// This can either be used on its own, or be part of a shared
/// [LiquidGlassLayer], where all shapes will blend together.
///
/// The simplest use of this widget is to create a [LiquidGlass] on its own
/// layer:
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlass(
///     shape: LiquidGlassSquircle(
///       borderRadius: Radius.circular(10),
///     ),
///     child: FlutterLogo(),
///   );
/// }
/// ```
///
/// If you want multiple shapes to blend together, you need to construct your
/// own [LiquidGlassLayer], and place this widget inside of there using the
/// [LiquidGlass.inLayer] constructor.
///
/// See the [LiquidGlassLayer] documentation for more information.
class LiquidGlass extends StatelessWidget {
  /// Creates a new [LiquidGlass] on its own layer with the given [child],
  /// [shape], and [settings].
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    super.key,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
  }) : _settings = settings;

  const LiquidGlass.inBlendGroup({
    required this.child,
    required this.shape,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : _settings = null;

  /// Maximum number of shapes supported per layer.
  static const int maxShapesPerLayer = 16;

  /// The child of this widget.
  ///
  /// You can choose whether this should be rendered "inside" of the glass, or
  /// on top using [glassContainsChild].
  final Widget child;

  /// {@template liquid_glass_renderer.LiquidGlass.shape}
  /// The shape of this glass.
  ///
  /// This is the shape of the glass that will be rendered.
  /// {@endtemplate}
  final LiquidShape shape;

  /// Whether this glass should be rendered "inside" of the glass, or on top.
  ///
  /// If it is rendered inside, the color tint
  /// of the glass will affect the child, and it will also be refracted.
  ///
  /// Defaults to `false`.
  final bool glassContainsChild;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.none], so [child] will not be clipped.
  final Clip clipBehavior;

  final LiquidGlassSettings? _settings;

  @override
  Widget build(BuildContext context) {
    return switch (_settings) {
      null => _RawLiquidGlass(
          glassLink: LiquidGlassLinkScope.of(context).link,
          shape: shape,
          glassContainsChild: glassContainsChild,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            clipBehavior: clipBehavior,
            child: GlassGlowLayer(child: child),
          ),
        ),
      final settings => LiquidGlassBlendGroup(
          settings: settings,
          child: _RawLiquidGlass(
            glassLink: LiquidGlassLinkScope.of(context).link,
            shape: shape,
            glassContainsChild: glassContainsChild,
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              clipBehavior: clipBehavior,
              child: GlassGlowLayer(child: child),
            ),
          ),
        ),
    };
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.glassContainsChild,
    required this.glassLink,
  });

  final LiquidShape shape;

  final bool glassContainsChild;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      glassContainsChild: glassContainsChild,
      glassLink: glassLink,
      blendGroup: LiquidGlassBlendGroup.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..glassContainsChild = glassContainsChild
      ..glassLink = glassLink
      ..blendGroup = LiquidGlassBlendGroup.of(context);
  }
}

@internal
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    required LiquidShape shape,
    required bool glassContainsChild,
    required GlassLink glassLink,
    LiquidGlassBlendGroup? blendGroup,
  })  : _shape = shape,
        _glassContainsChild = glassContainsChild,
        _glassLink = glassLink,
        _blendGroup = blendGroup;

  late LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    _updateGlassLink();
  }

  bool _glassContainsChild = true;
  bool get glassContainsChild => _glassContainsChild;
  set glassContainsChild(bool value) {
    if (_glassContainsChild == value) return;
    _glassContainsChild = value;
    _updateGlassLink();
  }

  GlassLink? _glassLink;
  set glassLink(GlassLink? value) {
    if (_glassLink == value) return;
    _unregisterFromParentLayer();
    _glassLink = value;
    _registerWithLink();
  }

  LiquidGlassBlendGroup? _blendGroup;
  LiquidGlassBlendGroup get blendGroup => _blendGroup!;
  set blendGroup(LiquidGlassBlendGroup value) {
    if (_blendGroup == value) return;
    final oldBlendGroup = _blendGroup;
    _blendGroup = value;
    _updateGlassLink(oldBlendGroup);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registerWithLink();
  }

  @override
  void detach() {
    _unregisterFromParentLayer();
    super.detach();
  }

  void _registerWithLink() {
    if (_glassLink != null) {
      _glassLink!.registerShape(
        _blendGroup!,
        this,
        _shape,
        glassContainsChild: _glassContainsChild,
      );
    }
  }

  void _unregisterFromParentLayer() {
    _glassLink?.unregisterShape(
      blendGroup,
      this,
    );
    _glassLink = null;
  }

  void _updateGlassLink([LiquidGlassBlendGroup? oldBlendGroup]) {
    _glassLink?.updateShape(
      blendGroup,
      this,
      _shape,
      glassContainsChild: _glassContainsChild,
      oldBlendGroup: oldBlendGroup,
    );
  }

  late Path _lastPath;

  @override
  void performLayout() {
    super.performLayout();
    // Notify parent layer when our layout changes
    _lastPath = shape.getOuterPath(Offset.zero & size);
    _glassLink?.notifyShapeLayoutChanged(blendGroup, this);
  }

  Matrix4? lastTransform;

  @override
  void paint(PaintingContext context, Offset offset) {}

  void paintFromLayer(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }

  Path getPath() {
    return _lastPath;
  }
}

/// A group of liquid glass shapes that blend together.
///
/// Glass shapes below this widget will automatically be part of this layer.
class LiquidGlassBlendGroup extends InheritedWidget {
  /// Creates a new [LiquidGlassBlendGroup].
  const LiquidGlassBlendGroup({
    required super.child,
    this.settings = const LiquidGlassSettings(),
    this.blendPx = 20,
    super.key,
  });

  final LiquidGlassSettings settings;

  final double blendPx;

  static LiquidGlassBlendGroup of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiquidGlassBlendGroup>();
    assert(scope != null, 'No LiquidGlassBlendGroup found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassBlendGroup ||
        oldWidget.settings != settings;
  }
}
