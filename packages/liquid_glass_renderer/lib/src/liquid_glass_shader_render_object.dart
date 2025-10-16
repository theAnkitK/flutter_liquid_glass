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
    required this.blendShader,
    required this.squircleShader,
    required this.ovalShader,
    required this.rRectShader,
    required GlassLink glassLink,
    required double devicePixelRatio,
  })  : _glassLink = glassLink,
        _devicePixelRatio = devicePixelRatio {
    _glassLink.addListener(onLinkNotification);
    onLinkNotification();
  }

  final FragmentShader blendShader;
  final FragmentShader squircleShader;
  final FragmentShader ovalShader;
  final FragmentShader rRectShader;

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
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  List<PaintableLiquidGlassElement> _cachedElements = [];
  List<PaintableLiquidGlassElement> get cachedElements => _cachedElements;

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    final shapes = updateShapes();

    if (shapes.isEmpty) {
      super.paint(context, offset);
      return;
    }

    super.paint(context, offset);

    paintLiquidGlass(context, offset, shapes);
  }

  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<PaintableLiquidGlassElement> shapes,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<PaintableLiquidGlassElement> shapes, {
    required bool glassContainsChild,
  }) {
    final renderObjects = shapes
        .map((s) => switch (s) {
              PaintableGlassShape(:final renderObject) => [renderObject],
              PaintableGlassGroup(:final shapes) =>
                shapes.map((e) => e.renderObject),
            })
        .expand((e) => e)
        .toList();

    for (final renderObject in renderObjects) {
      if (renderObject.glassContainsChild == glassContainsChild) {
        final transform = renderObject.getTransformTo(this);

        context.pushTransform(
          true,
          offset,
          transform,
          renderObject.paintFromLayer,
        );
      }
    }
  }

  /// NEEDS TO BE CALLED AT THE BEGINNING OF PAINT
  List<PaintableLiquidGlassElement> updateShapes() {
    if (!glassLink.hasShapes) {
      _cachedElements = [];
      return _cachedElements;
    }

    final elements = <PaintableLiquidGlassElement>[];

    for (final MapEntry(key: group, value: renderObjects)
        in glassLink.shapes.entries) {
      if (renderObjects.isEmpty) {
        continue;
      }

      // This is a single shape
      if (renderObjects.length == 1) {
        final renderObject = renderObjects.keys.first;
        final settings = group.settings;
        if (settings.thickness <= 0) {
          continue;
        }

        final transform = renderObject.getTransformTo(this);

        final dpr = Matrix4.diagonal3Values(
          devicePixelRatio,
          devicePixelRatio,
          1,
        );

        final shape = RawShape.fromLiquidGlassShape(
          renderObject.shape,
          rect: MatrixUtils.transformRect(
            dpr.multiplied(transform),
            Offset.zero & renderObject.size,
          ),
        );

        elements.add(
          PaintableGlassShape(
            shape: shape,
            renderObject: renderObject,
            transform: transform,
            settings: settings,
            glassContainsChild: renderObject.glassContainsChild,
          ),
        );
        continue;
      }

      // This is a group of shapes
      final shapesInGroup = <PaintableGlassShapeInGroup>[];
      Rect? groupBounds;
      for (final renderObject in renderObjects.keys) {
        final settings = group.settings;
        if (settings.thickness <= 0) {
          continue;
        }
        final transform = renderObject.getTransformTo(this);
        final dpr = Matrix4.diagonal3Values(
          devicePixelRatio,
          devicePixelRatio,
          1,
        );
        final shape = RawShape.fromLiquidGlassShape(
          renderObject.shape,
          rect: MatrixUtils.transformRect(
            dpr.multiplied(transform),
            Offset.zero & renderObject.size,
          ),
        );
        shapesInGroup.add(
          PaintableGlassShapeInGroup(
            shape: shape,
            renderObject: renderObject,
            transform: transform,
            glassContainsChild: renderObject.glassContainsChild,
          ),
        );
        groupBounds = groupBounds?.expandToInclude(shape.rect) ?? shape.rect;
      }
      if (shapesInGroup.isNotEmpty) {
        elements.add(
          PaintableGlassGroup(
            shapes: shapesInGroup,
            settings: group.settings,
            blendValue: group.blendPx,
            paintBounds: groupBounds!,
          ),
        );
      }
    }

    return _cachedElements = elements;
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

@internal
sealed class PaintableLiquidGlassElement {
  const PaintableLiquidGlassElement({
    required this.settings,
  });

  /// The settings to paint with
  final LiquidGlassSettings settings;

  /// The bounds over which the shape should paint
  Rect get paintBounds;

  double? get blendValue => null;

  FragmentShader prepareShader({
    required FragmentShader blendShader,
    required FragmentShader squircleShader,
    required FragmentShader ovalShader,
    required FragmentShader rRectShader,
    required double devicePixelRatio,
  });

  @protected
  void setSettingsOnShader(FragmentShader shader) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setColor(settings.glassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.chromaticAberration,
          settings.thickness,
          blendValue ?? 0,
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
}

/// Represents a single shape that will be painted with a single layer.
class PaintableGlassShape extends PaintableLiquidGlassElement {
  const PaintableGlassShape({
    required this.shape,
    required this.renderObject,
    required this.transform,
    required super.settings,
    required this.glassContainsChild,
  });

  /// The shape to paint
  final RawShape shape;

  /// The RenderObject that owns the shape
  final RenderLiquidGlass renderObject;

  /// The transform from the shape's RenderObject to the layer
  final Matrix4 transform;

  final bool glassContainsChild;

  @override
  Rect get paintBounds => shape.rect;

  @override
  FragmentShader prepareShader({
    required FragmentShader blendShader,
    required FragmentShader squircleShader,
    required FragmentShader ovalShader,
    required FragmentShader rRectShader,
    required double devicePixelRatio,
  }) {
    final shader = switch (shape.type) {
      RawShapeType.ellipse => ovalShader,
      RawShapeType.roundedRectangle => rRectShader,
      RawShapeType.squircle || RawShapeType.none => squircleShader,
    };

    setSettingsOnShader(shader);

    shader.setFloatUniforms(initialIndex: 16, (value) {
      value
        ..setFloat(shape.rect.center.dx)
        ..setFloat(shape.rect.center.dy)
        ..setFloat(shape.rect.size.width)
        ..setFloat(shape.rect.size.height)
        ..setFloat(shape.cornerRadius * devicePixelRatio);
    });

    return shader;
  }
}

class PaintableGlassGroup extends PaintableLiquidGlassElement {
  const PaintableGlassGroup({
    required this.shapes,
    required super.settings,
    required this.paintBounds,
    required this.blendValue,
  });

  /// The shapes in the group
  final List<PaintableGlassShapeInGroup> shapes;

  final Rect paintBounds;

  final double blendValue;

  @override
  FragmentShader prepareShader({
    required FragmentShader blendShader,
    required FragmentShader squircleShader,
    required FragmentShader ovalShader,
    required FragmentShader rRectShader,
    required double devicePixelRatio,
  }) {
    setSettingsOnShader(blendShader);

    blendShader.setFloatUniforms(initialIndex: 16, (value) {
      value.setFloat(shapes.length.toDouble());
      for (var i = 0; i < shapes.length; i++) {
        final shape = shapes[i].shape;

        value
          ..setFloat(shape.type.index.toDouble())
          ..setFloat(shape.rect.center.dx)
          ..setFloat(shape.rect.center.dy)
          ..setFloat(shape.rect.size.width)
          ..setFloat(shape.rect.size.height)
          ..setFloat(shape.cornerRadius * devicePixelRatio);
      }
    });
    return blendShader;
  }
}

class PaintableGlassShapeInGroup {
  const PaintableGlassShapeInGroup({
    required this.shape,
    required this.renderObject,
    required this.transform,
    required this.glassContainsChild,
  });

  /// The shape to paint
  final RawShape shape;

  /// The RenderObject that owns the shape
  final RenderLiquidGlass renderObject;

  /// The transform from the shape's RenderObject to the layer
  final Matrix4 transform;

  final bool glassContainsChild;
}
