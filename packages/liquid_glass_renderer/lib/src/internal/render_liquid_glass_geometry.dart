import 'dart:ui';

import 'package:flutter/foundation.dart' hide internal;
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/links.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/shape_in_layer.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

/// The state of liquid glass geometry, used to determine if it needs to be
/// updated.
enum LiquidGlassGeometryState {
  /// The geometry is up to date and does not need to be updated.
  updated,

  /// The geometry might need to be updated, but could potentially be reused.
  ///
  /// This happens mainly when all of the geometry itself is unchanged, but all
  /// of the geometry has been uniformly transformed.
  ///
  /// In this case, we can use the existing geometry matte and transform it to
  /// save GPU cycles.
  mightNeedUpdate,

  /// The geometry definitely needs to be updated.
  needsUpdate,
}

/// A base class for any render object that represents liquid glass geometry.
///
/// This will paint to the screen normally, but use a [GeometryLink] to gather
/// shape information and generate a geometry matte using the provided
/// [geometryShader].
@internal
abstract class RenderLiquidGlassGeometry extends RenderProxyBox
    with ChangeNotifier {
  /// Creates a new [RenderLiquidGlassGeometry] with the given
  /// [geometryShader].
  RenderLiquidGlassGeometry({
    required this.geometryShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
  })  : _settings = settings,
        _devicePixelRatio = devicePixelRatio {
    _updateShaderWithSettings(settings, devicePixelRatio);
  }

  /// The logger for liquid glass geometry.
  final Logger logger = Logger('lgr.LiquidGlassGeometry');

  /// The shader that generates the geometry matte.
  final FragmentShader geometryShader;

  LiquidGlassSettings? _settings;

  /// The settings used for liquid glass rendering.
  ///
  /// If these settings change in a way that affects geometry, the geometry
  /// will be marked as needing an update.
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      logger.finer('$hashCode geometry rebuild due to settings change.');
      markGeometryNeedsUpdate(force: true);
    }

    _settings = value;
    _updateShaderWithSettings(value, _devicePixelRatio);
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// The device pixel ratio used for rendering.
  ///
  /// If this changes, the geometry will be marked as needing an update.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markGeometryNeedsUpdate(force: true);
    _updateShaderWithSettings(settings, value);
    markNeedsPaint();
  }

  GeometryLink? _link;

  /// The link that provides shape information to this geometry.
  GeometryLink get link => _link!;

  set link(GeometryLink value) {
    if (_link == value) return;
    _link?.removeListener(_onLinkUpdate);
    _link = value;
    value.addListener(_onLinkUpdate);
    markNeedsPaint();
  }

  /// The current state of the geometry.
  @visibleForTesting
  @protected
  LiquidGlassGeometryState geometryState = LiquidGlassGeometryState.needsUpdate;

  /// The current geometry matte image.
  Geometry? geometry;

  void _onLinkUpdate() {
    // One of the shapes might have changed.
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  /// Marks the geometry as needing an update.
  ///
  /// If [force] is true, the geometry will be marked as definitely needing an
  /// update. Otherwise, it will be marked as possibly needing an update,
  /// unless it is already marked as definitely needing an update.
  @protected
  void markGeometryNeedsUpdate({bool force = false}) {
    final newState = force
        ? LiquidGlassGeometryState.needsUpdate
        : LiquidGlassGeometryState.mightNeedUpdate;

    geometryState = switch ((geometryState, newState)) {
      (LiquidGlassGeometryState.needsUpdate, _) =>
        LiquidGlassGeometryState.needsUpdate,
      (_, LiquidGlassGeometryState.needsUpdate) =>
        LiquidGlassGeometryState.needsUpdate,
      _ => LiquidGlassGeometryState.mightNeedUpdate,
    };
  }

  @override
  @mustCallSuper
  void paint(PaintingContext context, Offset offset) {
    _maybeRebuildGeometry();
    super.paint(context, offset);
  }

  @override
  @mustCallSuper
  void dispose() {
    geometry?.dispose();
    super.dispose();
  }

  /// Should be called from within [paint] to maybe rebuild the [geometry].
  void _maybeRebuildGeometry() {
    final (layerBounds, shapes, anyShapeChangedInLayer) = _gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null) {
      logger.finer('$hashCode Skipping geometry rebuild.');
      geometryState = LiquidGlassGeometryState.updated;
      return;
    }

    logger.finer('$hashCode Rebuilding geometry');

    geometry?.dispose();
    geometry = null;

    if (shapes.isEmpty) {
      return;
    }

    final image = _renderGeometryToImage(layerBounds, shapes);

    geometry = Geometry(
      matte: image,
      geometryBounds: layerBounds,
      shapes: shapes,
    );

    // We have updated the geometry.
    notifyListeners();
  }

  /// Gathers all shapes and computes them in both layer and screen space
  /// Returns (layerBounds, shapes, anyShapeChangedInLayer)
  (
    Rect bounds,
    List<ShapeGeometry> geometries,
    bool needsUpdate,
  ) _gatherShapeData() {
    final shapes = <ShapeGeometry>[];
    final cachedShapes = geometry?.shapes ?? [];

    var anyShapeChangedInLayer =
        cachedShapes.length != link.shapeEntries.length;

    Rect? layerBounds;

    for (final (
          index,
          MapEntry(
            key: renderObject,
            value: (shape, glassContainsChild),
          ),
        ) in link.shapeEntries.indexed) {
      if (!renderObject.attached || !renderObject.hasSize) continue;

      try {
        final shapeData = _computeShapeInfo(
          renderObject,
          shape,
          glassContainsChild,
        );
        shapes.add(shapeData);

        layerBounds = layerBounds?.expandToInclude(shapeData.layerBounds) ??
            shapeData.layerBounds;

        final existingShape =
            cachedShapes.length > index ? cachedShapes[index] : null;

        if (existingShape == null) {
          anyShapeChangedInLayer = true;
        } else if (existingShape.layerBounds != shapeData.layerBounds) {
          anyShapeChangedInLayer = true;
        }
      } catch (e) {
        debugPrint('Failed to compute shape info: $e');
      }
    }

    return (
      layerBounds ?? Rect.zero,
      shapes,
      anyShapeChangedInLayer,
    );
  }

  void _updateShaderWithSettings(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  ) {
    geometryShader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        settings.effectiveChromaticAberration,
        settings.effectiveThickness,
        settings.blend * devicePixelRatio,
      ]);
    });
  }

  Image _renderGeometryToImage(
    Rect geometryBounds,
    List<ShapeGeometry> shapes,
  ) {
    final bounds =
        geometryBounds.inflate(settings.blend).snapToPixels(devicePixelRatio);

    final width = (bounds.width * devicePixelRatio).ceil();
    final height = (bounds.height * devicePixelRatio).ceil();

    geometryShader.setFloatUniforms((value) {
      value
        ..setFloat(width.toDouble())
        ..setFloat(height.toDouble());
    });

    _updateGeometryShaderShapes(shapes);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..shader = geometryShader;

    final leftPixel = (geometryBounds.left * devicePixelRatio).roundToDouble();
    final topPixel = (geometryBounds.top * devicePixelRatio).roundToDouble();

    canvas
      // This translation might seem redundant, but we do it to ensure pixel
      // snapping
      ..translate(-leftPixel, -topPixel)
      ..drawRect(
        Rect.fromLTWH(leftPixel, topPixel, width.toDouble(), height.toDouble()),
        paint,
      );

    final pic = recorder.endRecording();
    return pic.toImageSync(width, height);
  }

  ShapeGeometry _computeShapeInfo(
    RenderLiquidGlass renderObject,
    LiquidShape shape,
    bool glassContainsChild,
  ) {
    if (!hasSize) {
      throw StateError(
        'Cannot compute shape info for $renderObject because '
        '$this LiquidGlassGeometry has no size yet.',
      );
    }

    if (!renderObject.hasSize) {
      throw StateError(
        'Cannot compute shape info for LiquidGlass $renderObject because it '
        'has no size yet.',
      );
    }

    // Layer space: for painting shape contents with correct transforms
    final transformToGeometry = renderObject.getTransformTo(this);
    final layerRect = MatrixUtils.transformRect(
      transformToGeometry,
      Offset.zero & renderObject.size,
    );

    return ShapeGeometry(
      renderObject: renderObject,
      shape: shape,
      glassContainsChild: glassContainsChild,
      layerBounds: layerRect,
      relativeLayerBounds: RelativeRect.fromLTRB(
        layerRect.left / size.width,
        layerRect.top / size.height,
        1 - layerRect.right / size.width,
        1 - layerRect.bottom / size.height,
      ),
      shapeToLayer: transformToGeometry,
    );
  }

  /// Uploads shape data to geometry shader in screen space coordinates
  void _updateGeometryShaderShapes(
    List<ShapeGeometry> shapes,
  ) {
    if (shapes.length > LiquidGlass.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlass.maxShapesPerLayer} shapes are supported at '
        'the moment!',
      );
    }

    geometryShader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloat(shapes.length.toDouble());
      for (final shape in shapes) {
        final center = shape.layerBounds.center;
        final size = shape.layerBounds.size;
        value
          ..setFloat(shape.rawShapeType.shaderIndex)
          ..setFloat((center.dx) * devicePixelRatio)
          ..setFloat((center.dy) * devicePixelRatio)
          ..setFloat(size.width * devicePixelRatio)
          ..setFloat(size.height * devicePixelRatio)
          ..setFloat(shape.rawCornerRadius * devicePixelRatio);
      }
    });
  }
}

/// Represents a current snapshot of the geometry used for liquid glass
/// rendering.
@immutable
@internal
class Geometry {
  const Geometry({
    required this.matte,
    required this.geometryBounds,
    required this.shapes,
  });

  /// The matte image representing the geometry.
  final Image matte;

  /// The bounds of the geometry in the coordinate space of its
  /// [RenderLiquidGlassGeometry] parent.
  final Rect geometryBounds;

  final List<ShapeGeometry> shapes;

  /// Disposes of the resources used by the geometry.
  @mustCallSuper
  void dispose() {
    matte.dispose();
  }
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return effectiveThickness != other.effectiveThickness ||
        refractiveIndex != other.refractiveIndex ||
        blend != other.blend;
  }
}
