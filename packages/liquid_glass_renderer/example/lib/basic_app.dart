import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:rivership/rivership.dart';

void main() {
  runApp(LiquidGlassCanvas(child: CupertinoApp(home: BasicApp())));
}

final settingsNotifier = ValueNotifier(
  LiquidGlassSettings(
    thickness: 20,
    blur: 10,
    refractiveIndex: 1.2,
    lightIntensity: .8,
    saturation: 1.2,
    lightAngle: pi / 4,
    glassColor: Colors.white.withValues(alpha: 0.2),
  ),
);

class BasicApp extends HookWidget {
  const BasicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = useState(0);

    final light = useRotatingAnimationController();

    return GestureDetector(
      onTap: () {
        SettingsSheet(
          settingsNotifier: settingsNotifier,
          lightAngleAnimation: light,
        ).show(context);
      },
      child: LiquidGlassCanvas(
        child: CupertinoPageScaffold(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => AspectRatio(
                        aspectRatio: 2,
                        child: Image.network(
                          'https://picsum.photos/1000/500?random=$index',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Center(
                child: ListenableBuilder(
                  listenable: Listenable.merge([settingsNotifier, light]),
                  builder: (context, child) {
                    final settings = settingsNotifier.value.copyWith(
                      glassColor: CupertinoTheme.of(
                        context,
                      ).barBackgroundColor.withValues(alpha: 0.4),
                    );
                    return Column(
                      spacing: 16,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LiquidGlassBlendGroup(
                          settings: settings,
                          blendPx: 40,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 16,
                            children: [
                              LiquidStretch(
                                child: LiquidGlass.inBlendGroup(
                                  shape: LiquidRoundedSuperellipse(
                                    borderRadius: Radius.circular(20),
                                  ),
                                  child: GlassGlow(
                                    child: SizedBox.square(
                                      dimension: 100,
                                      child: Center(child: Text('REAL')),
                                    ),
                                  ),
                                ),
                              ),
                              LiquidStretch(
                                child: LiquidGlass.inBlendGroup(
                                  shape: LiquidRoundedSuperellipse(
                                    borderRadius: Radius.circular(20),
                                  ),
                                  child: GlassGlow(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox.square(
                                        dimension: 100,
                                        child: Center(child: Text('FAKE')),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        LiquidStretch(
                          child: LiquidGlass(
                            shape: LiquidRoundedSuperellipse(
                              borderRadius: Radius.circular(20),
                            ),
                            child: GlassGlow(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  width: 400,
                                  height: 64,
                                  child: Center(child: Text('FAKE')),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Blink extends StatelessWidget {
  const Blink({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SequenceMotionBuilder(
      converter: SingleMotionConverter(),
      sequence: StepSequence.withMotions([
        (0.0, Motion.linear(Duration(seconds: 1))),
        (1.0, Motion.linear(Duration(seconds: 1))),
        (1.0, Motion.linear(Duration(seconds: 1))),
      ], loop: LoopMode.loop),
      builder: (context, value, phase, child) =>
          Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
