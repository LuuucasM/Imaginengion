#version 460
#extension GL_GOOGLE_include_directive : require

#include "common/constants.glsl"
#include "common/structs.glsl"
#include "common/math.glsl"

layout(location = 0) out vec4 oFragColor;

layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
layout(set = 2, binding = 1) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
layout(set = 2, binding = 2) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
layout(set = 3, binding = 0) uniform CameraUBO { CameraData Data; } Camera;

#include "common/surfacecolor.glsl"
#include "common/sdfs.glsl"
#include "common/raymarch.glsl"

void main() {
    vec2 uv = Camera.Data.RayScale * gl_FragCoord.xy + Camera.Data.RayOffset;
    vec3 ray_dir = QuatRotate(normalize(vec3(uv, -1.0)), Camera.Rotation);

    oFragColor = RayMarch(Camera.Data.Position, ray_dir);
}
