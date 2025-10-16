import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_link_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shader_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// {@template liquid_glass_canvas}
/// A widget that provides a liquid glass effect to its descendants.
///
/// You need to wrap this around any widget that you want liquid glass to be
/// painted on top of.
///
/// The most common use case would be to wrap this around each of your screens,
/// but you can also wrap your app in it.
///
/// Any [LiquidGlass] or [LiquidGlassBlendGroup] widgets inside of this will
/// be painted after [child], but in the order that they were declared in the
/// widget tree.
/// {@endtemplate}
class LiquidGlassCanvas extends StatefulWidget {
  /// {@macro liquid_glass_canvas}
  const LiquidGlassCanvas({
    required this.child,
    super.key,
  });

  /// The child that you want liquid glass to be painted on top of.
  final Widget child;

  @override
  State<LiquidGlassCanvas> createState() => _LiquidGlassCanvasState();
}

class _LiquidGlassCanvasState extends State<LiquidGlassCanvas> {
  late final _glassLink = GlassLink();

  @override
  void dispose() {
    _glassLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassLinkScope(
      link: _glassLink,
      child: MultiShaderBuilder(
        (context, shaders, child) {
          return _RawLiquidGlassFilter(
            blendShader: shaders[0],
            squircleShader: shaders[1],
            ovalShader: shaders[1],
            rRectShader: shaders[1],
            geometryBlendedShader: shaders[2],
            geometrySquircleShader: shaders[3],
            finalRenderShader: shaders[4],
            glassLink: _glassLink,
            child: child,
          );
        },
        assetKeys: [
          liquidGlassBlendedShader,
          liquidGlassSquircleShader,
          liquidGlassGeometryBlendedShader,
          liquidGlassGeometrySquircleShader,
          liquidGlassFinalRenderShader,
        ],
        child: widget.child,
      ),
    );
  }
}

class _RawLiquidGlassFilter extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassFilter({
    required this.blendShader,
    required this.squircleShader,
    required this.ovalShader,
    required this.rRectShader,
    required this.geometryBlendedShader,
    required this.geometrySquircleShader,
    required this.finalRenderShader,
    required this.glassLink,
    required super.child,
  });

  final FragmentShader blendShader;
  final FragmentShader squircleShader;
  final FragmentShader ovalShader;
  final FragmentShader rRectShader;
  final FragmentShader geometryBlendedShader;
  final FragmentShader geometrySquircleShader;
  final FragmentShader finalRenderShader;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassFilter(
      blendShader: blendShader,
      squircleShader: squircleShader,
      ovalShader: ovalShader,
      rRectShader: rRectShader,
      geometryBlendedShader: geometryBlendedShader,
      geometrySquircleShader: geometrySquircleShader,
      finalRenderShader: finalRenderShader,
      glassLink: glassLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlassFilter renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..glassLink = glassLink;
  }
}

class _RenderLiquidGlassFilter extends LiquidGlassShaderRenderObject {
  _RenderLiquidGlassFilter({
    required super.blendShader,
    required super.squircleShader,
    required super.ovalShader,
    required super.rRectShader,
    required FragmentShader geometryBlendedShader,
    required FragmentShader geometrySquircleShader,
    required FragmentShader finalRenderShader,
    required super.devicePixelRatio,
    required super.glassLink,
  })  : _geometryBlendedShader = geometryBlendedShader,
        _geometrySquircleShader = geometrySquircleShader,
        _finalRenderShader = finalRenderShader;

  final FragmentShader _geometryBlendedShader;
  final FragmentShader _geometrySquircleShader;
  final FragmentShader _finalRenderShader;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  _ShaderLayer? get layer => super.layer as _ShaderLayer?;

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<PaintableLiquidGlassElement> shapes,
  ) {
    final layer = (this.layer ??= _ShaderLayer(
      blendShader: blendShader,
      squircleShader: squircleShader,
      ovalShader: ovalShader,
      rRectShader: rRectShader,
      geometryBlendedShader: _geometryBlendedShader,
      geometrySquircleShader: _geometrySquircleShader,
      finalRenderShader: _finalRenderShader,
    ))
      ..elements = shapes
      ..devicePixelRatio = devicePixelRatio
      ..bounds = offset & size
      ..offset = offset;

    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: true,
    );
    context.pushLayer(
      layer,
      (context, offset) {
        context.paintChild(child!, offset);
      },
      offset,
    );

    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: false,
    );
  }
}

/// Custom composited layer that handles the liquid glass shader effect
/// with a captured child image
class _ShaderLayer extends OffsetLayer {
  _ShaderLayer({
    required this.blendShader,
    required this.squircleShader,
    required this.ovalShader,
    required this.rRectShader,
    required this.geometryBlendedShader,
    required this.geometrySquircleShader,
    required this.finalRenderShader,
  });

  final FragmentShader blendShader;
  final FragmentShader squircleShader;
  final FragmentShader ovalShader;
  final FragmentShader rRectShader;
  final FragmentShader geometryBlendedShader;
  final FragmentShader geometrySquircleShader;
  final FragmentShader finalRenderShader;

  List<PaintableLiquidGlassElement> _elements = [];
  List<PaintableLiquidGlassElement> get elements => _elements;
  set elements(List<PaintableLiquidGlassElement> value) {
    if (listEquals(_elements, value)) return;
    _elements = value;
    markNeedsAddToScene();
  }

  Rect? _bounds;
  Rect get bounds => _bounds!;
  set bounds(Rect value) {
    if (_bounds == value) return;
    _bounds = value;
    markNeedsAddToScene();
  }

  double? _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio!;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  final Map<int, ui.Image> _blurredImages = {};
  final Map<PaintableLiquidGlassElement, ui.Image> _geometryTextures = {};

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (elements.isEmpty) {
      addChildrenToScene(builder);
      return;
    }

    _captureImages();
    _generateGeometryTextures();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(1 / devicePixelRatio)
      ..drawImage(_blurredImages[0]!, Offset.zero, ui.Paint());

    for (final element in elements) {
      final geometryTexture = _geometryTextures[element];
      if (geometryTexture != null) {
        final shader = finalRenderShader
          ..setFloat(0, bounds.width)
          ..setFloat(1, bounds.height)
          ..setImageSampler(0, _blurredImages[element.settings.blur.round()]!)
          ..setImageSampler(1, geometryTexture);

        element.setFinalRenderUniforms(shader, devicePixelRatio);

        canvas.drawRect(
          Rect.fromLTWH(
            element.paintBounds.left,
            element.paintBounds.top,
            element.paintBounds.width,
            element.paintBounds.height,
          ),
          ui.Paint()..shader = shader,
        );
      }
    }

    final picture = recorder.endRecording();
    builder.addPicture(offset, picture);
  }

  void _captureImages() {
    _clearImages();

    final image = _blurredImages[0] = _captureImage();

    final uniqueBlurs = elements.map((e) => e.settings.blur.round()).toSet();
    for (final blur in uniqueBlurs) {
      final blurred = _buildBlurredImage(image, blur.toDouble());
      if (blurred != null) {
        _blurredImages[blur] = blurred;
      }
    }
  }

  ui.Image _captureImage() {
    final builder = ui.SceneBuilder();
    engineLayer = builder.pushOffset(
      -offset.dx * devicePixelRatio,
      -offset.dy * devicePixelRatio,
      oldLayer: engineLayer as ui.OffsetEngineLayer?,
    );
    {
      final transform = Matrix4.diagonal3Values(
        devicePixelRatio,
        devicePixelRatio,
        1,
      );
      builder.pushTransform(transform.storage);

      addChildrenToScene(builder);

      builder.pop();
    }
    builder.pop();

    return builder.build().toImageSync(
          (devicePixelRatio * bounds.width).ceil(),
          (devicePixelRatio * bounds.height).ceil(),
        );
  }

  ui.Image? _buildBlurredImage(ui.Image image, double blur) {
    if (blur <= 0) {
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final paint = ui.Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: ui.TileMode.mirror,
      );

    canvas.drawImage(image, Offset.zero, paint);

    final picture = recorder.endRecording();
    return picture.toImageSync(image.width, image.height);
  }

  void _generateGeometryTextures() {
    _clearGeometryTextures();

    for (final element in elements) {
      final geometryShader = switch (element) {
        PaintableGlassShape() => geometrySquircleShader,
        PaintableGlassGroup() => geometryBlendedShader,
      };

      geometryShader
        ..setFloat(0, bounds.width)
        ..setFloat(1, bounds.height);

      element.setGeometryUniforms(geometryShader, devicePixelRatio);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      canvas.drawRect(
        Offset.zero & (element.paintBounds.size),
        ui.Paint()..shader = geometryShader,
      );

      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        (element.paintBounds.width).ceil(),
        (element.paintBounds.height).ceil(),
      );

      _geometryTextures[element] = image;
    }
  }

  void _clearImages() {
    _blurredImages
      ..forEach((key, value) => value.dispose())
      ..clear();
  }

  void _clearGeometryTextures() {
    _geometryTextures
      ..forEach((key, value) => value.dispose())
      ..clear();
  }

  @override
  void dispose() {
    _clearImages();
    _clearGeometryTextures();
    super.dispose();
  }
}
