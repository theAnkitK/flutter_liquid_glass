// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared utilities for encoding and decoding displacement data

// Encode a 16-bit float value into two 8-bit channels
// Input: value in range [minVal, maxVal]
// Output: vec2 with values in range [0, 1]
vec2 encode16bit(float value, float minVal, float maxVal) {
    float normalized = clamp((value - minVal) / (maxVal - minVal), 0.0, 1.0);
    float scaled = normalized * 65535.0;
    float high = floor(scaled / 256.0);
    float low = scaled - high * 256.0;
    return vec2(high / 255.0, low / 255.0);
}

// Decode a 16-bit float value from two 8-bit channels
// Input: vec2 with values in range [0, 1]
// Output: value in range [minVal, maxVal]
float decode16bit(vec2 encoded, float minVal, float maxVal) {
    float high = encoded.x * 255.0;
    float low = encoded.y * 255.0;
    float scaled = high * 256.0 + low;
    float normalized = scaled / 65535.0;
    return mix(minVal, maxVal, normalized);
}

// Encode displacement vector (x, y) into RGBA channels
// Uses 16-bit precision per component
// Assumes displacement range is approximately [-maxDisplacement, +maxDisplacement]
vec4 encodeDisplacement(vec2 displacement, float maxDisplacement) {
    vec2 encodedX = encode16bit(displacement.x, -maxDisplacement, maxDisplacement);
    vec2 encodedY = encode16bit(displacement.y, -maxDisplacement, maxDisplacement);
    return vec4(encodedX, encodedY);
}

// Decode displacement vector from RGBA channels
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    float x = decode16bit(encoded.rg, -maxDisplacement, maxDisplacement);
    float y = decode16bit(encoded.ba, -maxDisplacement, maxDisplacement);
    return vec2(x, y);
}
