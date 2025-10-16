// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final render shader for liquid glass - uses precomputed displacement textures
// This shader is very fast since most computation was done in the geometry pass

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "render.glsl"
#include "sdf.glsl"
#include "displacement_encoding.glsl"

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec4 uGlassColor;
layout(location = 2) uniform vec4 uLightConfig;
layout(location = 3) uniform vec2 uLightDirection;
layout(location = 4) uniform vec4 uDisplacementParams;
layout(location = 5) uniform vec2 uElementOffset;
layout(location = 6) uniform vec2 uElementSize;
layout(location = 7) uniform float uChromaticAberration;
layout(location = 8) uniform float uThickness;

float uLightIntensity = uLightConfig.y;
float uAmbientStrength = uLightConfig.z;
float uSaturation = uLightConfig.w;
float maxDisplacement = uDisplacementParams.x;

uniform sampler2D uBlurredTexture;
uniform sampler2D uDisplacementTexture;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif
    
    vec2 localCoord = fragCoord - uElementOffset;
    vec2 displacementUV = localCoord / uElementSize;
    
    #ifdef IMPELLER_TARGET_OPENGLES
        displacementUV.y = 1.0 - displacementUV.y;
    #endif
    
    if (displacementUV.x < 0.0 || displacementUV.x > 1.0 || 
        displacementUV.y < 0.0 || displacementUV.y > 1.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec4 encoded = texture(uDisplacementTexture, displacementUV);
    
    if (encoded.a < 0.01) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec2 displacement = decodeDisplacement(encoded, maxDisplacement);
    
    vec2 invUSize = 1.0 / uSize;
    
    vec4 refractColor;
    if (uChromaticAberration < 0.001) {
        vec2 refractedUV = screenUV + displacement * invUSize;
        refractColor = texture(uBlurredTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);

        vec2 redUV = screenUV + redOffset * invUSize;
        vec2 greenUV = screenUV + displacement * invUSize;
        vec2 blueUV = screenUV + blueOffset * invUSize;

        float red = texture(uBlurredTexture, redUV).r;
        vec4 greenSample = texture(uBlurredTexture, greenUV);
        float blue = texture(uBlurredTexture, blueUV).b;

        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    
vec4 finalColor = applyGlassColor(refractColor, uGlassColor);
    
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);
    
    vec4 bgSample = texture(uBlurredTexture, screenUV);
    fragColor = mix(bgSample, finalColor, 1.0);
}
