const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const SceneLayer = @import("../SceneLayer.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

//scripts
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnSceneStartScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub const Category: ComponentCategory = .Unique;
    bit: u1 = 0,
    pub fn Deinit(_: *OnSceneStartScript) !void {}
};
