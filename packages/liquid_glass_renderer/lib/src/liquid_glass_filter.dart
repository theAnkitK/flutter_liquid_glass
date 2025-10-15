import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
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
            settings: widget.settings,
            glassLink: _glassLink,
            child: child!,
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
    required super.child,
    required this.settings,
    required this.glassLink,
  });

  final LiquidGlassSettings settings;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassFilter(
      settings: settings,
      glassLink: glassLink,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassFilter renderObject,
  ) {
    renderObject.settings = settings;
    renderObject.glassLink = glassLink;
  }
}

class RenderLiquidGlassFilter extends RenderProxyBox {
  RenderLiquidGlassFilter({
    required LiquidGlassSettings settings,
    required GlassLink glassLink,
    RenderBox? child,
  })  : _settings = settings,
        _glassLink = glassLink,
        super(child);

  late LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings != value) {
      _settings = value;
      markNeedsPaint();
    }
  }

  late GlassLink _glassLink;
  GlassLink get glassLink => _glassLink;
  set glassLink(GlassLink value) {
    if (_glassLink != value) {
      _glassLink = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}
