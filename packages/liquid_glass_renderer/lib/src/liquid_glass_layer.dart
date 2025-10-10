// ignore_for_file: avoid_setters_without_getters

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// Represents a layer of multiple [LiquidGlass] shapes that can flow together
/// and have shared [LiquidGlassSettings].
///
/// If you create a [LiquidGlassLayer] with one or more [LiquidGlass.inLayer]
/// widgets, the liquid glass effect will be rendered where this layer is.
/// Make sure not to stack any other widgets between the [LiquidGlassLayer] and
/// the [LiquidGlass] widgets, otherwise the liquid glass effect will be behind
/// them.
///
/// > [!WARNING]
/// > A maximum of 16 shapes are supported per layer due to Impeller's
/// > uniform buffer limits.
///
/// ## Example
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlassLayer(
///     child: Column(
///       children: [
///         LiquidGlass.inLayer(
///           shape: LiquidGlassSquircle(
///             borderRadius: Radius.circular(10),
///           ),
///           child: SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///         const SizedBox(height: 100),
///         LiquidGlass.inLayer(
///           shape: LiquidGlassSquircle(
///             borderRadius: Radius.circular(50),
///           ),
///           child: SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///       ],
///     ),
///   );
/// }
class LiquidGlassLayer extends StatefulWidget {
  /// Creates a new [LiquidGlassLayer] with the given [child] and [settings].
  const LiquidGlassLayer({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    this.restrictThickness = true,
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// {@template liquid_glass_renderer.restrict_thickness}
  /// If set to true, the thickness of all shapes in this layer will be
  /// restricted to the dimensions of the smallest shape.
  ///
  /// This will prevent artifacts on shapes that are thicker than wide/tall
  /// {@endtemplate}
  final bool restrictThickness;

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    if (!ImageFilter.isShaderFilterSupported) {
      assert(
        ImageFilter.isShaderFilterSupported,
        'liquid_glass_renderer is only supported when using Impeller at the '
        'moment. Please enable Impeller, or check '
        'ImageFilter.isShaderFilterSupported before you use liquid glass '
        'widgets.',
      );
      return widget.child;
    }

    return RepaintBoundary(
      child: ShaderBuilder(
        assetKey: liquidGlassShader,
        (context, shader, child) => _RawShapes(
          shader: shader,
          settings: widget.settings,
          debugRenderRefractionMap: false,
          restrictThickness: widget.restrictThickness,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.shader,
    required this.settings,
    required this.debugRenderRefractionMap,
    required this.restrictThickness,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;
  final bool restrictThickness;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
      restrictThickness: restrictThickness,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..debugRenderRefractionMap = debugRenderRefractionMap
      ..restrictThickness = restrictThickness;
  }
}

/// Maximum number of shapes supported per layer due to Impeller's uniform
/// buffer limit
const int _maxShapesPerLayer = 16;

/// Cached metrics that are calculated for all shapes in a layer
typedef _ShapesMetrics = ({
  double thickness,
  Rect boundingBox,
});

@internal
class ShapeInLayer extends ComputedShapeInfo {
  ShapeInLayer({
    required super.renderObject,
    required super.shape,
    required super.glassContainsChild,
    required super.globalBounds,
    required super.globalTransform,
    required this.transformToLayer,
    required this.rawShape,
  });

  factory ShapeInLayer.fromComputed({
    required ComputedShapeInfo info,
    required Matrix4 toLayer,
    required RawShape rawShape,
  }) {
    return ShapeInLayer(
      renderObject: info.renderObject,
      rawShape: rawShape,
      shape: info.shape,
      glassContainsChild: info.glassContainsChild,
      globalBounds: info.globalBounds,
      globalTransform: info.globalTransform,
      transformToLayer: toLayer,
    );
  }

  /// The transform from the shape's render object to the layer's render object.
  final Matrix4 transformToLayer;

  /// The shape data used to render this shape in the shader.
  final RawShape rawShape;
}

@internal
class RenderLiquidGlassLayer extends RenderProxyBox {
  RenderLiquidGlassLayer({
    required double devicePixelRatio,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required bool restrictThickness,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _debugRenderRefractionMap = debugRenderRefractionMap,
        _restrictThickness = restrictThickness,
        _glassLink = GlassLink() {
    // Listen to glass link changes instead of using a ticker
    _glassLink.addListener(_onGlassLinkChanged);
  }

  @override
  bool get alwaysNeedsCompositing => true;

  bool _restrictThickness;
  set restrictThickness(bool value) {
    if (_restrictThickness == value) return;
    _restrictThickness = value;
    _cache = null;
    markNeedsPaint();
  }

  final GlassLink _glassLink;

  /// The GlassLink that shapes can use to report their state.
  GlassLink get glassLink => _glassLink;

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _cache = null;
    markNeedsPaint();
  }

  final FragmentShader _shader;

  LiquidGlassSettings _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final thicknessChanged = _settings.thickness != value.thickness;
    final blurChanged = _settings.blur != value.blur;
    _settings = value;
    if (thicknessChanged || blurChanged) {
      _cache = null;
    }
    markNeedsPaint();
  }

  bool _debugRenderRefractionMap;
  set debugRenderRefractionMap(bool value) {
    if (_debugRenderRefractionMap == value) return;
    _debugRenderRefractionMap = value;
    markNeedsPaint();
  }

  // Cache for computed shapes to avoid recomputing on every paint
  (List<ShapeInLayer>, _ShapesMetrics)? _cache;

  void _onGlassLinkChanged() {
    _cache = null;
    markNeedsPaint();
  }

  (List<ShapeInLayer>, _ShapesMetrics) _collectShapes() {
    final result = <ShapeInLayer>[];
    final computedShapes = _glassLink.computedShapes;

    // Check shape count limit
    if (computedShapes.length > _maxShapesPerLayer) {
      throw UnsupportedError(
        'Only $_maxShapesPerLayer shapes are supported at the moment!',
      );
    }

    var boundingBox = Rect.zero;
    var thickness = _settings.thickness;

    for (final shapeInfo in computedShapes) {
      final renderObject = shapeInfo.renderObject;

      final scale = _getScaleFromTransform(shapeInfo.globalTransform);

      final shapeInLayer = ShapeInLayer.fromComputed(
        info: shapeInfo,
        toLayer: renderObject.getTransformTo(this),
        rawShape: RawShape.fromLiquidGlassShape(
          shapeInfo.shape,
          center: shapeInfo.globalBounds.center,
          size: shapeInfo.globalBounds.size,
          scale: scale,
        ),
      );
      result.add(shapeInLayer);

      boundingBox = boundingBox.expandToInclude(shapeInLayer.rawShape.rect);

      if (_restrictThickness &&
          thickness > shapeInLayer.rawShape.size.shortestSide) {
        thickness = shapeInLayer.rawShape.size.shortestSide;
      }
    }

    // Inflate by blend plus one logical pixel to avoid artifacts on edges
    boundingBox =
        boundingBox.inflate((_settings.blend + 1) * _devicePixelRatio);

    return (result, (thickness: thickness, boundingBox: boundingBox));
  }

  /// Extracts the geometric mean of X and Y scale factors from a transform.
  ///
  /// This is used to scale corner radii when shapes are transformed by Flutter
  /// widgets like [FittedBox] or [Transform]. The position and size are already
  /// correctly transformed via [MatrixUtils.transformRect], but corner radii
  /// need explicit scaling.
  ///
  /// **Design Tradeoff**: Instead of passing full Matrix3 transforms to the
  /// shader, we extract scale on the CPU once per frame
  /// per shape and only send 6 floats per shape to the shader.
  ///
  /// **Performance**: Optimized with fast path for axis-aligned transforms
  /// (FittedBox, Transform.scale) using direct matrix access. Handles rotated
  /// and skewed transforms with minimal overhead.
  ///
  /// **Limitation**: For non-uniform scaling with rotation, the geometric mean
  /// may not perfectly match visual appearance in all cases, but provides good
  /// results for common UI transforms while keeping shader cost at zero.
  double _getScaleFromTransform(Matrix4 transform) {
    final m = transform.storage;
    final scaleX = m[0];
    final scaleY = m[5];

    if (m[1] == 0 && m[4] == 0) {
      return sqrt(scaleX.abs() * scaleY.abs());
    }

    final a = m[0];
    final b = m[1];
    final c = m[4];
    final d = m[5];
    final scaleXSq = a * a + b * b;
    final scaleYSq = c * c + d * d;
    return sqrt(sqrt(scaleXSq * scaleYSq));
  }

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _blurLayerHandle = LayerHandle<BackdropFilterLayer>();
  final _clipLayerHandle = LayerHandle<ClipPathLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    // Use cached shapes if available, otherwise compute them
    final (shapes, metrics) = _cache ??= _collectShapes();

    if (shapes.isEmpty) {
      super.paint(context, offset);
      return;
    }

    if (_settings.thickness <= 0) {
      _paintShapeContents(context, offset, shapes, glassContainsChild: true);
      _paintShapeContents(context, offset, shapes, glassContainsChild: false);
      super.paint(context, offset);
      return;
    }

    final shapeCount = min(_maxShapesPerLayer, shapes.length);

    final (:thickness, :boundingBox) = metrics;

    _shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setFloats([
          boundingBox.left * _devicePixelRatio,
          boundingBox.top * _devicePixelRatio,
          boundingBox.right * _devicePixelRatio,
          boundingBox.bottom * _devicePixelRatio,
        ])
        ..setColor(_settings.glassColor)
        ..setFloats([
          _settings.refractiveIndex,
          _settings.chromaticAberration,
          thickness,
          _settings.blend * _devicePixelRatio,
          _settings.lightAngle,
          _settings.lightIntensity,
          _settings.ambientStrength,
          _settings.saturation,
          shapeCount.toDouble(),
        ])
        ..setOffset(
          Offset(
            cos(_settings.lightAngle),
            sin(_settings.lightAngle),
          ),
        );

      for (var i = 0; i < shapeCount; i++) {
        final shape = i < shapes.length ? shapes[i].rawShape : RawShape.none;
        value
          ..setFloat(shape.type.index.toDouble())
          ..setFloat(shape.center.dx * _devicePixelRatio)
          ..setFloat(shape.center.dy * _devicePixelRatio)
          ..setFloat(shape.size.width * _devicePixelRatio)
          ..setFloat(shape.size.height * _devicePixelRatio)
          ..setFloat(shape.cornerRadius * _devicePixelRatio);
      }
    });

    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.shader(_shader);

    final blurLayer = (_blurLayerHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.blur(
        tileMode: TileMode.mirror,
        sigmaX: _settings.blur,
        sigmaY: _settings.blur,
      );

    final clipPath = Path();
    for (final shape in shapes) {
      clipPath.addPath(
        shape.renderObject.getPath(),
        offset,
        matrix4: shape.transformToLayer.storage,
      );
    }

    final clipLayer = (_clipLayerHandle.layer ??= ClipPathLayer())
      ..clipPath = clipPath
      ..clipBehavior = Clip.hardEdge;

    context
      // First we push the clipped blur layer
      ..pushLayer(
        clipLayer,
        (context, offset) {
          context.pushLayer(
            blurLayer,
            (context, offset) {
              // If glass contains child we paint it above blur but below shader
              _paintShapeContents(
                context,
                offset,
                shapes,
                glassContainsChild: true,
              );
            },
            offset,
          );
        },
        offset,
      )
      // Then we push the shader layer on top
      ..pushLayer(
        shaderLayer,
        (context, offset) => _paintShapeContents(
          context,
          offset,
          shapes,
          glassContainsChild: false,
        ),
        offset,
      );

    super.paint(context, offset);
  }

  @override
  void dispose() {
    _glassLink
      ..removeListener(_onGlassLinkChanged)
      ..dispose();
    _blurLayerHandle.layer = null;
    _shaderHandle.layer = null;
    _clipLayerHandle.layer = null;
    super.dispose();
  }

  void _paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayer> shapes, {
    required bool glassContainsChild,
  }) {
    for (final ShapeInLayer(:renderObject, :transformToLayer) in shapes) {
      if (renderObject.glassContainsChild == glassContainsChild) {
        context.pushTransform(
          true,
          offset,
          transformToLayer,
          renderObject.paintFromLayer,
        );
      }
    }
  }
}
