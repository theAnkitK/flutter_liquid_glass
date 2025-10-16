// ignore_for_file: dead_code, deprecated_member_use_from_same_package

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
import 'package:meta/meta.dart';

@internal
enum RawShapeType {
  none,
  squircle,
  ellipse,
  roundedRectangle,
}

@internal
class RawShape with EquatableMixin {
  const RawShape({
    required this.type,
    required this.rect,
    required this.cornerRadius,
  });

  factory RawShape.fromLiquidGlassShape(
    LiquidShape shape, {
    required Rect rect,
    double scale = 1.0,
  }) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        _assertSameRadius(shape.borderRadius);
        return RawShape(
          type: RawShapeType.squircle,
          rect: rect,
          cornerRadius: shape.borderRadius.x * scale,
        );
      case LiquidOval():
        return RawShape(
          type: RawShapeType.ellipse,
          rect: rect,
          cornerRadius: 0,
        );
      case LiquidRoundedRectangle():
        _assertSameRadius(shape.borderRadius);
        return RawShape(
          type: RawShapeType.roundedRectangle,
          rect: rect,
          cornerRadius: shape.borderRadius.x * scale,
        );
    }
  }

  static const none = RawShape(
    type: RawShapeType.none,
    rect: Rect.zero,
    cornerRadius: 0,
  );

  final RawShapeType type;
  final Rect rect;

  final double cornerRadius;

  @override
  List<Object?> get props => [type, rect, cornerRadius];
}

void _assertSameRadius(Radius borderRadius) {
  assert(
    borderRadius.x == borderRadius.y,
    'The radius must have equal x and y values for a liquid glass shape.',
  );
}
