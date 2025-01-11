const std = @import("std");
const builtin = @import("builtin");
const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;

const Renderer = @This();

var RenderManager: *Renderer = undefined;

const MaxTri: u32 = 20_000;
const MaxVerticies: u32 = MaxTri * 3;
const MaxIndices: u32 = MaxTri * 3;

mEngineAllocator: std.mem.Allocator,
mRenderContext: RenderContext,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    const new_render_context = RenderContext.Init();
    RenderManager = try EngineAllocator.create(Renderer);
    RenderManager.* = .{
        .mEngineAllocator = EngineAllocator,
        .mRenderContext = new_render_context,
        .mRenderer2D = Renderer2D.Init(
            MaxTri,
            MaxVerticies,
            MaxIndices,
            new_render_context.GetMaxTextureImageSlots(),
        ),
        .mRenderer3D = Renderer3D.Init(),
    };
}

pub fn Deinit() void {
    RenderManager.mEngineAllocator.destroy(RenderManager);
}

pub fn SwapBuffers() void {
    RenderManager.mRenderContext.SwapBuffers();
}
