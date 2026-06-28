const std = @import("std");
const spirv = std.spirv;

const FragShader = @import("SDFFragShaderBase.zig");
const FragShaderBase = FragShader.FragShaderBase;

const PushConstants = @import("IM").PushConstants;
const QuadData = @import("IM").QuadData;
const GlyphData = @import("IM").GlyphData;
const ShadingData = @import("IM").ShadingData;
const RayMarcher = @import("IM").RayMarcher;
const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Vec4 = @import("IM").Vec4;
const Quat = @import("IM").Quat;

// layout(location = 0) out vec4 oFragColor
const oFragColor = FragShader.oFragColor;

// layout(set = 3, binding = 0) uniform PushConstnats
const CameraUBO = FragShader.CameraUBO;

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
const Textures = FragShader.Textures;
//layout(set = 2, binding = 1) uniform sampler
const Overlay = FragShader.Overlay;

//layout(set = 2, binding = 2) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
const QuadsSSBO = FragShader.QuadsSSBO;

//layout(set = 2, binding = 3) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
const GlyphsSSBO = FragShader.GlyphsSSBO;

//layout(set = 2, binding = 4) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
const ShadingSSBO = FragShader.ShadingSSBO;

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    const frag = spirv.frag_coord;

    const uv_screen = Vec2(f32){ .x = frag[0] / CameraUBO.mViewportWidth, .y = frag[1] / CameraUBO.mViewportHeight };

    const overlay_color = FragShader.SampleTexture(.{ .descriptor = .{ .set = 2, .binding = 1 } }, uv_screen.ToVector());

    //check xyz to see if its been filled or not
    if (overlay_color[0] != 0 or overlay_color[1] != 0 or overlay_color[2] != 0) {
        oFragColor.* = overlay_color;
    } else {
        oFragColor.* = FragShaderBase(
            CameraUBO.*,
            QuadsSSBO.*,
            GlyphsSSBO.*,
            ShadingSSBO.*,
            Textures,
            Vec4(f32){ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1.0 },
        );
    }
}
