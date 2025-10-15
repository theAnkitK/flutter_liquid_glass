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
  ) {
    final layer = (this.layer ??= _ShaderLayer(
      shader: shader,
      offset: Offset.zero,
      devicePixelRatio: devicePixelRatio,
      bounds: Offset.zero & size,
    ))
      ..shader = shader
      ..devicePixelRatio = devicePixelRatio
      ..bounds = Offset.zero & size
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
    required super.offset,
    required FragmentShader shader,
    required double devicePixelRatio,
    required Rect bounds,
  })  : _shader = shader,
        _devicePixelRatio = devicePixelRatio,
        _bounds = bounds;

  FragmentShader _shader;
  FragmentShader get shader => _shader;
  set shader(FragmentShader value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsAddToScene();
  }

  Rect _bounds;
  Rect get bounds => _bounds;
  set bounds(Rect value) {
    if (_bounds == value) return;
    _bounds = value;
    markNeedsAddToScene();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  ui.Image? childImage;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _captureChildLayer();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    if (childImage != null) {
      shader
        ..setImageSampler(0, childImage!)
        ..setFloat(0, bounds.width * devicePixelRatio)
        ..setFloat(1, bounds.height * devicePixelRatio);

      canvas
        ..scale(1 / devicePixelRatio)
        ..drawRect(
          offset & bounds.size * devicePixelRatio,
          ui.Paint()..shader = shader,
        );
    }

    final picture = recorder.endRecording();
    builder.addPicture(offset, picture);
  }

  void _captureChildLayer() {
    childImage?.dispose();
    childImage = _buildMaskImage();
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

  @override
  void dispose() {
    childImage?.dispose();
    super.dispose();
  }
}
