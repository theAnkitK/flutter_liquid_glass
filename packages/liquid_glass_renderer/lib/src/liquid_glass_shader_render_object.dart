import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:meta/meta.dart';

@internal
abstract class LiquidGlassShaderRenderObject extends RenderProxyBox {
  LiquidGlassShaderRenderObject({
    required FragmentShader shader,
    required GlassLink glassLink,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
  })  : _shader = shader,
        _settings = settings,
        _glassLink = glassLink,
        _devicePixelRatio = devicePixelRatio {
    _glassLink.addListener(onLinkNotification);
    onLinkNotification();
    setSettingsUniforms();
  }

  GlassLink _glassLink;

  /// The GlassLink that shapes can use to report their state.
  GlassLink get glassLink => _glassLink;
  set glassLink(GlassLink value) {
    if (_glassLink == value) return;
    _glassLink.removeListener(onLinkNotification);
    _glassLink = value;
    value.addListener(onLinkNotification);
    markNeedsPaint();
  }

  @protected
  void onLinkNotification() {
    setShapeUniforms();
    markNeedsPaint();
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    setSettingsUniforms();
    markNeedsPaint();
  }

  FragmentShader? _shader;
  FragmentShader get shader => _shader!;
  set shader(FragmentShader value) {
    if (_shader == value) return;
    _shader = value;
    setSettingsUniforms();
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  List<(RenderLiquidGlass, RawShape)> _cachedShapes = [];
  List<(RenderLiquidGlass, RawShape)> get cachedShapes => _cachedShapes;

  void setSettingsUniforms() {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setColor(settings.glassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.chromaticAberration,
          settings.thickness,
          settings.blend * devicePixelRatio,
          settings.lightAngle,
          settings.lightIntensity,
          settings.ambientStrength,
          settings.saturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        );
    });
  }

  void setShapeUniforms() {
    final shapes = cachedShapes;
    final shapeCount = shapes.length;

    // Check shape count limit
    if (shapeCount > LiquidGlass.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlass.maxShapesPerLayer} shapes are supported at '
        'the moment!',
      );
    }

    shader.setFloatUniforms(initialIndex: 16, (value) {
      value.setFloat(shapeCount.toDouble());
      for (var i = 0; i < shapeCount; i++) {
        final shape = i < shapes.length ? shapes[i].$2 : RawShape.none;
        value
          ..setFloat(shape.type.index.toDouble())
          ..setFloat(shape.center.dx * devicePixelRatio)
          ..setFloat(shape.center.dy * devicePixelRatio)
          ..setFloat(shape.size.width * devicePixelRatio)
          ..setFloat(shape.size.height * devicePixelRatio)
          ..setFloat(shape.cornerRadius * devicePixelRatio);
      }
    });
  }

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    final shapes = updateShapes();

    if (shapes.isEmpty) {
      super.paint(context, offset);
      return;
    }

    if (settings.thickness <= 0) {
      paintShapeContents(context, offset, shapes, glassContainsChild: true);
      paintShapeContents(context, offset, shapes, glassContainsChild: false);
      super.paint(context, offset);
      return;
    }

    super.paint(context, offset);

    paintLiquidGlass(context, offset, shapes);
  }

  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes, {
    required bool glassContainsChild,
  }) {
    for (final (ro, _) in shapes) {
      if (ro.glassContainsChild == glassContainsChild) {
        final transform = ro.getTransformTo(this);

        context.pushTransform(
          true,
          offset,
          transform,
          ro.paintFromLayer,
        );
      }
    }
  }

  /// NEEDS TO BE CALLED AT THE BEGINNING OF PAINT
  List<(RenderLiquidGlass, RawShape)> updateShapes() {
    _cachedShapes = _collectShapes();
    setShapeUniforms();
    return _cachedShapes;
  }

  List<(RenderLiquidGlass, RawShape)> _collectShapes() {
    final result = <(RenderLiquidGlass, RawShape)>[];
    final computedShapes = glassLink.computedShapes;

    // Check shape count limit
    if (computedShapes.length > LiquidGlass.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlass.maxShapesPerLayer} shapes are supported at the '
        'moment!',
      );
    }

    for (final shapeInfo in computedShapes) {
      final renderObject = shapeInfo.renderObject;

      if (renderObject is RenderLiquidGlass) {
        final scale = _getScaleFromTransform(shapeInfo.transform);
        result.add(
          (
            renderObject,
            RawShape.fromLiquidGlassShape(
              shapeInfo.shape,
              center: shapeInfo.globalBounds.center,
              size: shapeInfo.globalBounds.size,
              scale: scale,
            ),
          ),
        );
      }
    }

    return result;
  }

  @override
  @mustCallSuper
  void dispose() {
    glassLink.removeListener(onLinkNotification);
    super.dispose();
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
}
