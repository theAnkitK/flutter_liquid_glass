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
            // TODO let's support all of it
            ovalShader: shaders[1],
            rRectShader: shaders[1],
            glassLink: _glassLink,
            child: child,
          );
        },
        assetKeys: [
          liquidGlassBlendedShader,
          liquidGlassSquircleShader,
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
    required this.glassLink,
    required super.child,
  });

  final FragmentShader blendShader;
  final FragmentShader squircleShader;
  final FragmentShader ovalShader;
  final FragmentShader rRectShader;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassFilter(
      blendShader: blendShader,
      squircleShader: squircleShader,
      ovalShader: ovalShader,
      rRectShader: rRectShader,
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
    required super.devicePixelRatio,
    required super.glassLink,
  });

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
        // The child is the whole app in this case
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
  });

  final FragmentShader blendShader;
  final FragmentShader squircleShader;
  final FragmentShader ovalShader;
  final FragmentShader rRectShader;

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

  ui.Image? _childImage;
  final Map<int, ui.Image> _blurredImages = {};

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (elements.isEmpty) {
      addChildrenToScene(builder);
      return;
    }

    _captureImages();

    final recorder = ui.PictureRecorder();
    engineLayer = builder.pushOffset(offset.dx, offset.dy);
    {
      final canvas = ui.Canvas(recorder)
        ..scale(1 / devicePixelRatio)
        // Draw the actual child first
        ..drawImage(_childImage!, offset, ui.Paint());

      for (final element in elements) {
        final shader = element.prepareShader(
          blendShader: blendShader,
          squircleShader: squircleShader,
          ovalShader: ovalShader,
          rRectShader: rRectShader,
          devicePixelRatio: devicePixelRatio,
        )
          ..setImageSampler(0, _blurredImages[element.settings.blur.round()]!)
          ..setFloat(0, bounds.width * devicePixelRatio)
          ..setFloat(1, bounds.height * devicePixelRatio);

        canvas.drawRect(
          element.paintBounds,
          ui.Paint()..shader = shader,
        );
      }

      final picture = recorder.endRecording();
      builder.addPicture(offset, picture);
    }
    builder.pop();
  }

  void _captureImages() {
    _clearImages();

    final image = _childImage = _captureImage();

    final uniqueBlurs = elements.map((e) => e.settings.blur.round()).toSet();
    for (final blur in uniqueBlurs) {
      _blurredImages[blur] = _buildBlurredImage(image, blur.toDouble());
    }
  }

  ui.Image _captureImage() {
    final builder = ui.SceneBuilder();

    final transform = Matrix4.diagonal3Values(
      devicePixelRatio,
      devicePixelRatio,
      1,
    );
    builder.pushTransform(transform.storage);

    addChildrenToScene(builder);

    builder.pop();

    return builder.build().toImageSync(
          (devicePixelRatio * bounds.width).ceil(),
          (devicePixelRatio * bounds.height).ceil(),
        );
  }

  ui.Image _buildBlurredImage(ui.Image image, double blur) {
    if (blur <= 0) {
      return image;
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

  void _clearImages() {
    _childImage?.dispose();
    _blurredImages
      ..forEach((key, value) => value.dispose())
      ..clear();
  }

  @override
  void dispose() {
    _clearImages();
    super.dispose();
  }
}
