import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shader_render_object.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

class LiquidGlassFilter extends StatefulWidget {
  const LiquidGlassFilter({
    super.key,
    required this.settings,
    required this.child,
  });

  final LiquidGlassSettings settings;
  final Widget child;

  @override
  State<LiquidGlassFilter> createState() => _LiquidGlassFilterState();
}

class _LiquidGlassFilterState extends State<LiquidGlassFilter> {
  late final _glassLink = GlassLink();

  @override
  void dispose() {
    _glassLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScope(
      settings: widget.settings,
      link: _glassLink,
      child: ShaderBuilder(
        (context, shader, child) {
          return _RawLiquidGlassFilter(
            shader: shader,
            settings: widget.settings,
            glassLink: _glassLink,
            child: child,
          );
        },
        assetKey: liquidGlassShader,
        child: widget.child,
      ),
    );
  }
}

class _RawLiquidGlassFilter extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassFilter({
    required this.shader,
    required this.settings,
    required this.glassLink,
    required super.child,
  });

  final FragmentShader shader;

  final LiquidGlassSettings settings;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassFilter(
      settings: settings,
      glassLink: glassLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassFilter renderObject,
  ) {
    renderObject
      ..shader = shader
      ..settings = settings
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..glassLink = glassLink;
  }
}

class RenderLiquidGlassFilter extends LiquidGlassShaderRenderObject {
  RenderLiquidGlassFilter({
    required super.devicePixelRatio,
    required super.settings,
    required super.glassLink,
    required super.shader,
  });

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  _ShaderLayer? get layer => super.layer as _ShaderLayer?;

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes,
    Path clipPath,
  ) {
    var shapeBounds = shapes.first.$2.topLeft & shapes.first.$2.size;

    for (final (_, rawShape) in shapes) {
      shapeBounds =
          shapeBounds.expandToInclude(rawShape.topLeft & rawShape.size);
    }

    final layer = (this.layer ??= _ShaderLayer())
      ..shapes = shapes
      ..shader = shader
      ..devicePixelRatio = devicePixelRatio
      ..bounds = offset & size
      ..offset = offset
      ..shapeBounds = shapeBounds
      ..clipPath = clipPath
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      ..markNeedsAddToScene();

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
  _ShaderLayer();

  List<(RenderLiquidGlass, RawShape)> _shapes = [];
  List<(RenderLiquidGlass, RawShape)> get shapes => _shapes;
  set shapes(List<(RenderLiquidGlass, RawShape)> value) {
    if (_shapes == value) return;
    _shapes = value;
    markNeedsAddToScene();
  }

  FragmentShader? _shader;
  FragmentShader get shader => _shader!;
  set shader(FragmentShader value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsAddToScene();
  }

  Rect? _bounds;
  Rect get bounds => _bounds!;
  set bounds(Rect value) {
    if (_bounds == value) return;
    _bounds = value;
    markNeedsAddToScene();
  }

  Rect? _shapeBounds;
  Rect get shapeBounds => _shapeBounds!;
  set shapeBounds(Rect value) {
    if (_shapeBounds == value) return;
    _shapeBounds = value;
    markNeedsAddToScene();
  }

  double? _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio!;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  Path? _clipPath;
  Path get clipPath => _clipPath!;
  set clipPath(Path value) {
    if (_clipPath == value) return;
    _clipPath = value;
    markNeedsAddToScene();
  }

  ui.Image? childImage;

  ui.Image? blurredImage;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _captureChildLayer();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    engineLayer = builder.pushOffset(offset.dx, offset.dy);
    {
      if (childImage != null) {
        shader
          ..setImageSampler(0, blurredImage!)
          ..setFloat(0, bounds.width * devicePixelRatio)
          ..setFloat(1, bounds.height * devicePixelRatio);
        canvas
          ..scale(1 / devicePixelRatio)
          ..drawImage(
            childImage!,
            bounds.topLeft * devicePixelRatio,
            ui.Paint(),
          );

        // TODO maybe make faster
        canvas.clipPath(
          clipPath.transform(
            Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1)
                .storage,
          ),
        );

        // Finally, draw liquid glass
        canvas.drawRect(
          (shapeBounds.topLeft * devicePixelRatio) &
              (shapeBounds.size * devicePixelRatio),
          ui.Paint()..shader = shader,
        );
      }

      final picture = recorder.endRecording();
      builder.addPicture(offset, picture);
    }
    builder.pop();
  }

  void _captureChildLayer() {
    childImage?.dispose();
    blurredImage?.dispose();
    childImage = _buildMaskImage();
    blurredImage = _buildBlurredImage(childImage!);
  }

  ui.Image _buildMaskImage() {
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

  ui.Image _buildBlurredImage(
    ui.Image source,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawImage(
      source,
      Offset.zero,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 10, sigmaY: 10, tileMode: ui.TileMode.decal),
    );

    final picture = recorder.endRecording();
    return picture.toImageSync((bounds.width * devicePixelRatio).ceil(),
        (bounds.height * devicePixelRatio).ceil());
  }

  @override
  void dispose() {
    childImage?.dispose();
    blurredImage?.dispose();
    super.dispose();
  }
}
