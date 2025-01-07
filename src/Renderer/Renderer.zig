const std = @import("std");
const builtin = @import("builtin");
const RenderContext = @import("RenderContext.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;

const Renderer = @This();

var RenderManager: *Renderer = undefined;

pub const RectVertex = struct {
    Position: Vec3f32,
    Color: Vec4f32,
    TexCoord: Vec2f32,
    TexIndex: f32,
    TilingFactor: f32,
};

pub const CircleVertex = struct {
    Position: Vec3f32,
    LocalPosition: Vec3f32,
    Color: Vec4f32,
    Thickness: f32,
    Fade: f32,
};

pub const EditorLineVertex = struct {
    Position: Vec3f32,
    Color: Vec4f32,
};

_EngineAllocator: std.mem.Allocator,
_RenderContext: RenderContext,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    RenderManager = try EngineAllocator.create(Renderer);
    RenderManager.* = .{
        ._EngineAllocator = EngineAllocator,
        ._RenderContext = RenderContext.Init(),
    };
}

pub fn Deinit() void {
    RenderManager._EngineAllocator.destroy(RenderManager);
}

pub fn SwapBuffers() void {
    RenderManager._RenderContext.SwapBuffers();
}
