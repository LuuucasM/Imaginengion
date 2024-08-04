const std = @import("std");
const builtin = @import("builtin");
const RenderContext = @import("RenderContext.zig");

const Renderer = @This();

var RenderManager: *Renderer = undefined;

_EngineAllocator: std.mem.Allocator,
_RenderContext: *RenderContext,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    RenderManager = try EngineAllocator.create(Renderer);
    RenderManager.* = .{
        ._EngineAllocator = EngineAllocator,
        ._RenderContext = try RenderContext.Init(EngineAllocator),
    };
}

pub fn Deinit() void {
    RenderManager._RenderContext.Deinit();
    RenderManager._EngineAllocator.destroy(RenderManager);
}

pub fn SwapBuffers() void {
    RenderManager._RenderContext.SwapBuffers();
}
