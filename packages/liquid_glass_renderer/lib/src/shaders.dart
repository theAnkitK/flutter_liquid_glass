// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/liquid_glass_renderer/';

@internal
final String liquidGlassShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass.frag';

@internal
final String liquidGlassBlendedShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_blended.frag';

@internal
final String liquidGlassSquircleShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_squircle.frag';

@internal
final String liquidGlassGeometryBlendedShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_geometry_blended.frag';

@internal
final String liquidGlassGeometrySquircleShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_geometry_squircle.frag';

@internal
final String liquidGlassFinalRenderShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_final_render.frag';
