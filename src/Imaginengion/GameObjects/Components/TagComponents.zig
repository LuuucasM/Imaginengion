const ComponentsList = @import("../Components.zig").ComponentsList;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../GameObjects/Entity.zig");
const ScriptType = @import("../../Assets/Assets/ScriptAsset.zig").ScriptType;

const WindowEventData = @import("../../Events/WindowEventData.zig");
const KeyboardPressedEvent = WindowEventData.KeyboardPressedEvent;

//scripts
pub const OnKeyPressedScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity, *const KeyboardPressedEvent) callconv(.c) bool;
    bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnKeyPressedScript";
    pub const Scripttype: ScriptType = .EntityInputPressed;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnKeyPressedScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *OnKeyPressedScript, _: *EngineContext) !void {}
};

pub const OnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity) callconv(.c) bool;
    bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnUpdate;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *OnUpdateScript, _: *EngineContext) !void {}
};
