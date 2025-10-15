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
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes,
  ) {
    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: true,
    );
    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: false,
    );
  }
}
