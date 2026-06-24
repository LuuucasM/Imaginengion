const std = @import("std");
const gpu = std.gpu;

const FragShader = @import("SDFFragShaderBase.zig");
const FragShaderBase = FragShader.FragShaderBase;
const Sampler2DArray = FragShader.Sampler2DArray;

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
const TexturesArray = FragShader.TexturesArray;

//layout(set = 2, binding = 2) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
const QuadsSSBO = FragShader.QuadsSSBO;

//layout(set = 2, binding = 3) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
const GlyphsSSBO = FragShader.GlyphsSSBO;

//layout(set = 2, binding = 4) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
const ShadingSSBO = FragShader.ShadingSSBO;

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    oFragColor.* = FragShaderBase(CameraUBO.*, QuadsSSBO.*, GlyphsSSBO.*, ShadingSSBO.*, TexturesArray);
}
