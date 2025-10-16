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

  void setGeometryUniforms(FragmentShader shader, double devicePixelRatio);

  void setFinalRenderUniforms(FragmentShader shader, double devicePixelRatio);

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
  void setGeometryUniforms(FragmentShader shader, double devicePixelRatio) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        0.0,
        settings.thickness,
        0.0,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setFloat(shape.rect.center.dx)
        ..setFloat(shape.rect.center.dy)
        ..setFloat(shape.rect.size.width)
        ..setFloat(shape.rect.size.height)
        ..setFloat(shape.cornerRadius * devicePixelRatio);
    });
  }

  @override
  void setFinalRenderUniforms(FragmentShader shader, double devicePixelRatio) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value.setColor(settings.glassColor);
    });

    shader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloats([
        settings.lightAngle,
        settings.lightIntensity,
        settings.ambientStrength,
        settings.saturation,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 10, (value) {
      value.setOffset(
        Offset(
          cos(settings.lightAngle),
          sin(settings.lightAngle),
        ),
      );
    });

    shader.setFloatUniforms(initialIndex: 12, (value) {
      value.setFloats([
        settings.thickness * 10.0,
        0.0,
        0.0,
        0.0,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 16, (value) {
      value.setOffset(shape.rect.topLeft);
    });

    shader.setFloatUniforms(initialIndex: 18, (value) {
      value
        ..setFloat(shape.rect.size.width)
        ..setFloat(shape.rect.size.height);
    });

    shader.setFloatUniforms(initialIndex: 20, (value) {
      value.setFloat(settings.chromaticAberration);
    });

    shader.setFloatUniforms(initialIndex: 21, (value) {
      value.setFloat(settings.thickness);
    });
  }

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
  void setGeometryUniforms(FragmentShader shader, double devicePixelRatio) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        0.0,
        settings.thickness,
        blendValue,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 6, (value) {
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
  }

  @override
  void setFinalRenderUniforms(FragmentShader shader, double devicePixelRatio) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value.setColor(settings.glassColor);
    });

    shader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloats([
        settings.lightAngle,
        settings.lightIntensity,
        settings.ambientStrength,
        settings.saturation,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 10, (value) {
      value.setOffset(
        Offset(
          cos(settings.lightAngle),
          sin(settings.lightAngle),
        ),
      );
    });

    shader.setFloatUniforms(initialIndex: 12, (value) {
      value.setFloats([
        settings.thickness * 10.0,
        0.0,
        0.0,
        0.0,
      ]);
    });

    shader.setFloatUniforms(initialIndex: 16, (value) {
      value.setOffset(paintBounds.topLeft);
    });

    shader.setFloatUniforms(initialIndex: 18, (value) {
      value
        ..setFloat(paintBounds.size.width)
        ..setFloat(paintBounds.size.height);
    });

    shader.setFloatUniforms(initialIndex: 20, (value) {
      value.setFloat(settings.chromaticAberration);
    });

    shader.setFloatUniforms(initialIndex: 21, (value) {
      value.setFloat(settings.thickness);
    });
  }

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
