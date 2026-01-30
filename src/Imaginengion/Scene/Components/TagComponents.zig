const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const SceneLayer = @import("../SceneLayer.zig");

//scripts
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;

    pub const Name: []const u8 = "OnSceneStartScript";
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnSceneStartScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *OnSceneStartScript, _: *EngineContext) !void {}
};
