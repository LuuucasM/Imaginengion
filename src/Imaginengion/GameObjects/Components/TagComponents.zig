const ComponentsList = @import("../Components.zig").ComponentsList;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../GameObjects/Entity.zig");
const InputPressedEvent = @import("../../Events/SystemEvent.zig").InputPressedEvent;
const ScriptType = @import("../../Assets/Assets/ScriptAsset.zig").ScriptType;

//scripts
pub const OnInputPressedScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity, *const InputPressedEvent) callconv(.c) bool;
    //bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnInputPressedScript";
    pub const Scripttype: ScriptType = .EntityInputPressed;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnInputPressedScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *OnInputPressedScript, _: *EngineContext) !void {}
};

pub const OnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity) callconv(.c) bool;
    //bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnUpdate;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateScript) {
                break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *OnUpdateScript, _: *EngineContext) !void {}
};
