import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassLinkScope extends InheritedWidget {
  /// Creates a new [LiquidGlassLinkScope].
  const LiquidGlassLinkScope({
    required super.child,
    required this.link,
    super.key,
  });

  final GlassLink link;

  static LiquidGlassLinkScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiquidGlassLinkScope>();
    assert(scope != null, 'No LiquidGlassScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassLinkScope || oldWidget.link != link;
  }
}
