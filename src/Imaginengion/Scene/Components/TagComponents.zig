const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig").EngineContext;
const SceneLayer = @import("../SceneLayer.zig");

//scripts
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *const SceneLayer) callconv(.C) bool;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnSceneStartScript) {
                break :blk i;
            }
        }
    };
    bit: u1 = 0,
    pub fn Deinit(_: *OnSceneStartScript) !void {}
};
