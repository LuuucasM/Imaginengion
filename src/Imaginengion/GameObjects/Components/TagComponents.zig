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
    pub const Editable: bool = false;
    pub fn Deinit(_: *OnInputPressedScript) !void {}
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnInputPressedScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn GetName(_: OnInputPressedScript) []const u8 {
        return "OnInputPressedScript";
    }

    pub fn GetInd(_: OnInputPressedScript) u32 {
        return @intCast(Ind);
    }
};

pub const OnUpdateInputScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const std.mem.Allocator, *const Entity) callconv(.c) bool;
    bit: u1 = 0,
    pub const Category: ComponentCategory = .Unique;
    pub const Editable: bool = false;
    pub fn Deinit(_: *OnUpdateInputScript) !void {}
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateInputScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn GetName(_: OnUpdateInputScript) []const u8 {
        return "OnUpdateInputScript";
    }

    pub fn GetInd(_: OnUpdateInputScript) u32 {
        return @intCast(Ind);
    }
};
