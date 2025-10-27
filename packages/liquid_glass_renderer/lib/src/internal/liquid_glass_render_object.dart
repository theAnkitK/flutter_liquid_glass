import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:meta/meta.dart';

@internal
bool debugPaintLiquidGlassGeometry = false;

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required GeometryRenderLink link,
    required this.renderShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    required BackdropKey? backdropKey,
  })  : _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _backdropKey = backdropKey,
        _link = link {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.object);

  final FragmentShader renderShader;

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    _link.removeListener(_onLinkNotification);
    value.addListener(_onLinkNotification);
    markNeedsPaint();
    _link = value;
  }

  // === Settings and Configuration ===

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _updateShaderSettings();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    _link.addListener(_onLinkNotification);
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    _link.removeListener(_onLinkNotification);
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    _needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        );
    });
  }

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    debugPaintLiquidGlassGeometry = false;
    if (link.shapeGeometries.isEmpty) {
      _geometryImage?.dispose();
      _geometryImage = null;
      markNeedsCompositingBitsUpdate();
      super.paint(context, offset);
      return;
    }

    final shapesWithGeometry = <(RenderLiquidGlassGeometry, Geometry)>[];

    Rect? boundingBox;

    for (final MapEntry(key: ro, value: geometry)
        in link.shapeGeometries.entries) {
      if (geometry == null) continue;

      shapesWithGeometry.add((ro, geometry));

      final geoBounds = geometry.bounds;
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    if (settings.effectiveThickness <= 0) {
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
      _geometryImage?.dispose();
      _geometryImage = null;
      markNeedsCompositingBitsUpdate();
      super.paint(context, offset);
      return;
    }

    if (_needsGeometryUpdate || _geometryImage == null) {
      final geometries = link.shapeGeometries.entries
          .where((entry) => entry.value != null)
          .map((entry) => (entry.key, entry.value!))
          .toList();

      _geometryImage?.dispose();
      if (_geometryImage == null) {
        markNeedsCompositingBitsUpdate();
      }
      _geometryImage = _buildGeometryImage(geometries);
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      _paintGlassEffect(
        context,
        offset,
        shapesWithGeometry,
        boundingBox ?? Rect.zero,
      );
    }

    super.paint(context, offset);
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      context.canvas
        ..save()
        ..transform(Matrix4.inverted(matteTransform).storage)
        ..scale(1 / devicePixelRatio)
        ..drawImage(geometryImage, offset * devicePixelRatio, Paint())
        ..restore();
    }
  }

  void _paintGlassEffect(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, Geometry)> shapes,
    Rect boundingBox,
  ) {
    if (_geometryImage case final geometryImage?) {
      renderShader.setImageSampler(1, geometryImage);
      paintLiquidGlass(context, offset, shapes, boundingBox);
    }
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, Geometry)> shapes,
    Rect boundingBox,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, Geometry)> shapes, {
    required bool insideGlass,
  }) {
    for (final (ro, _) in shapes) {
      ro.paintShapeContents(
        context,
        ro.geometry!.bounds.topLeft,
        insideGlass: insideGlass,
      );
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _geometryImage?.dispose();
    super.dispose();
  }

  bool _needsGeometryUpdate = true;

  void _onLinkNotification() {
    _needsGeometryUpdate = true;
  }

  /// The size that the geometry texture should have.
  Size get desiredMatteSize;

  Matrix4 get matteTransform;

  ui.Image _buildGeometryImage(
    List<(RenderLiquidGlassGeometry, Geometry)> geometries,
  ) {
    final size = desiredMatteSize * devicePixelRatio;
    logger.fine('$hashCode Building geometry image with '
        '${geometries.length} shapes at size $size');
    final recorder = ui.PictureRecorder();

    final canvas = Canvas(recorder)
      ..scale(devicePixelRatio)
      ..transform(matteTransform.storage)
      ..scale(1 / devicePixelRatio);

    for (final (renderObject, geometry) in geometries) {
      canvas
        ..save()
        ..transform(renderObject.getTransformTo(this).storage)
        ..translate(
          geometry.bounds.topLeft.dx * devicePixelRatio,
          geometry.bounds.topLeft.dy * devicePixelRatio,
        )
        ..drawPicture(geometry.matte)
        ..restore();
    }

    // Finalize image
    final picture = recorder.endRecording();
    return picture.toImageSync(
      size.width.ceil(),
      size.height.ceil(),
    );
  }
}

@internal
class InheritedGeometryRenderLink extends InheritedWidget {
  const InheritedGeometryRenderLink({
    required this.link,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;

  static GeometryRenderLink? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGeometryRenderLink>()
        ?.link;
  }

  @override
  bool updateShouldNotify(covariant InheritedGeometryRenderLink oldWidget) {
    return oldWidget.link != link;
  }
}

@internal
class GeometryRenderLink with ChangeNotifier {
  Map<RenderLiquidGlassGeometry, Geometry?> shapeGeometries = {};

  void registerGeometry(RenderLiquidGlassGeometry renderObject) {
    shapeGeometries[renderObject] = renderObject.geometry;
    notifyListeners();
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    shapeGeometries.remove(renderObject);
    notifyListeners();
  }

  void updateGeometry(
    RenderLiquidGlassGeometry renderObject,
    Geometry geometry,
  ) {
    shapeGeometries[renderObject] = geometry;
    notifyListeners();
  }
}
