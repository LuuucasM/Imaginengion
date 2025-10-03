const ComponentsList = @import("../Components.zig").ComponentsList;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig").EngineContext;
const Entity = @import("../../GameObjects/Entity.zig");
const InputPressedEvent = @import("../../Events/SystemEvent.zig").InputPressedEvent;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

//scripts
pub const OnInputPressedScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *const Entity, *const InputPressedEvent) callconv(.c) bool;
    bit: u1 = 0,
    pub const Category: ComponentCategory = .Unique;
    pub fn Deinit(_: *OnInputPressedScript) !void {}
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnInputPressedScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
};

pub const OnUpdateInputScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *const Entity) callconv(.c) bool;
    bit: u1 = 0,
    pub const Category: ComponentCategory = .Unique;
    pub fn Deinit(_: *OnUpdateInputScript) !void {}
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateInputScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
};
