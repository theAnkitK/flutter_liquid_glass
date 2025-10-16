// Copyright 2025, Tim Lehmann for whynotmake.it
//
// This shader is based on a bunch of sources:
// - https://www.shadertoy.com/view/wccSDf for the refraction
// - https://iquilezles.org/articles/distfunctions2d/ for SDFs
// - Gracious help from @dkwingsmt for the Squircle SDF
//
// Feel free to use this shader in your own projects, it'd be lovely if you could
// give some credit like I did here.

#version 460 core
precision mediump float;

#define DEBUG_NORMALS 0

#include <flutter/runtime_effect.glsl>
#include "render.glsl"
#include "sdf.glsl"

// Optimized uniform layout - grouped into vectors for better performance
layout(location = 0) uniform vec2 uSize;                    // width, height
layout(location = 1) uniform vec4 uGlassColor;             // r, g, b, a
layout(location = 2) uniform vec4 uOpticalProps;           // refractiveIndex, chromaticAberration, thickness, blend
layout(location = 3) uniform vec4 uLightConfig;            // angle, intensity, ambient, saturation
layout(location = 4) uniform vec2 uLightDirection;         // pre-computed cos(angle), sin(angle)

// Extract individual values for backward compatibility
float uChromaticAberration = uOpticalProps.y;
float uLightAngle = uLightConfig.x;
float uLightIntensity = uLightConfig.y;
float uAmbientStrength = uLightConfig.z;
float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uBlend = uOpticalProps.w; // ignored
float uSaturation = uLightConfig.w;

layout(location = 5) uniform float uShapeData[5];

uniform sampler2D uBlurredTexture;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
     
    // We invert screenUV Y on OpenGL to sample the textures correctly
    // fragCoord stays the same so shape positions are correct.
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif
    
    vec2 center = vec2(uShapeData[0], uShapeData[1]);
    vec2 size = vec2(uShapeData[2], uShapeData[3]);
    float cornerRadius = uShapeData[4];
    
    float sd = sdfSquircle(fragCoord - center, size / 2.0, cornerRadius);

    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);

    // Early discard for pixels outside glass shapes to reduce overdraw
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0);
        return;
    }

    vec3 normal = getNormal(sd, uThickness);
    
    // Use shared rendering pipeline
    fragColor = renderLiquidGlass(
        screenUV, 
        fragCoord, 
        uSize, 
        sd, 
        uThickness, 
        uRefractiveIndex, 
        uChromaticAberration, 
        uGlassColor, 
        uLightDirection, 
        uLightIntensity, 
        uAmbientStrength, 
        uBlurredTexture, 
        normal,
        foregroundAlpha,
        0.0,
        uSaturation
    );
    
    // Apply debug normals visualization using shared function
    #if DEBUG_NORMALS
        fragColor = debugNormals(fragColor, normal, true);
    #endif
}
