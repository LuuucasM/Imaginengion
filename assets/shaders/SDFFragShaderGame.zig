const std = @import("std");
const gpu = std.gpu;

const FragShaderBase = @import("SDFFragShaderBase.zig").FragShaderBase;

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
const oFragColor = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "oFragColor",
    .decoration = .{ .location = 0 },
});

// layout(set = 3, binding = 0) uniform PushConstnats
const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
//layout(set = 2, binding = 1) uniform sampler
//NOTE: samplers were just added to main on codeberg but probably should wait at least a few days
//to jump on it but its almost here :)

//layout(set = 2, binding = 2) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
const QuadsSSBO = @extern([*]addrspace(.storage_buffer) QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 3) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
const GlyphsSSBO = @extern([*]addrspace(.storage_buffer) GlyphData, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 4) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
const ShadingSSBO = @extern([*]addrspace(.storage_buffer) ShadingData, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

export fn main() callconv(.spirv_fragment) void {
    //const frag = gpu.frag_coord;

    //TODO: placeholder text so i dont forget since sampelrs are not out i dont actually know what it looks like exactly
    //const uv_screen = @Vector(2, f32){
    //    frag[0] / CameraUBO.mViewportWidth,
    //    frag[1] / CameraUBO.mViewportHeight,
    //};
    //const overlay_color = OverlaySampler.sample(uv_screen);
    //if (overlay_color.x != 0 or overlay_color.y != 0 or overlay_color.z != 0){
    //    oFragColor.* = overlay_color;
    //} else {
    //    FragShaderBase(oFragColor, CameraUBO, QuadsSSBO, GlyphsSSBO, ShadingSSBO);
    //}

    //NOTE: temporary while i dont have samplers
    FragShaderBase(oFragColor, CameraUBO, QuadsSSBO, GlyphsSSBO, ShadingSSBO);
}
