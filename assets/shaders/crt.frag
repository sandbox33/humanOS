#version 460 core

#include <flutter/runtime_effect.glsl>

// Static CRT scanlines for headers. No time uniform: nothing animates.
uniform vec2 uSize;
uniform float uStrength;

out vec4 fragColor;

void main() {
  vec2 pos = FlutterFragCoord().xy;
  float line = step(1.5, mod(pos.y, 3.0));
  float edge = min(pos.x, uSize.x - pos.x) / max(uSize.x, 1.0);
  float vignette = 1.0 - smoothstep(0.0, 0.12, edge);
  float alpha = uStrength * line + uStrength * 0.6 * vignette;
  fragColor = vec4(0.0, 0.0, 0.0, clamp(alpha, 0.0, 1.0));
}
