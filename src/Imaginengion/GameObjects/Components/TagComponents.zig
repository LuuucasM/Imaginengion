const ComponentsList = @import("../Components.zig").ComponentsList;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig").EngineContext;
const Entity = @import("../../GameObjects/Entity.zig");
const InputPressedEvent = @import("../../Events/SystemEvent.zig").InputPressedEvent;

//scripts
pub const OnInputPressedScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *Entity, *const InputPressedEvent) callconv(.C) bool;
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnInputPressedScript) {
                break :blk i;
            }
        }
    };
};

pub const OnUpdateInputScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *Entity) callconv(.C) bool;
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateInputScript) {
                break :blk i;
            }
        }
    };
};

pub const PrimaryCameraTag = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == PrimaryCameraTag) {
                break :blk i;
            }
        }
    };
};

pub const EditorCameraTag = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == EditorCameraTag) {
                break :blk i;
            }
        }
    };
};
