const ComponentsList = @import("../Components.zig").ComponentsList;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../GameObjects/Entity.zig");
const ScriptType = @import("../../Assets/Assets/ScriptAsset.zig").ScriptType;
const SceneLayer = @import("../SceneLayer.zig");

const WindowEventData = @import("../../Events/WindowEventData.zig");
const KeyboardPressedEvent = WindowEventData.KeyboardPressedEvent;

//ENTITY SCRIPTS
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

pub const EntityOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity) callconv(.c) bool;
    bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnUpdate;
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == EntityOnUpdateScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub fn Deinit(_: *EntityOnUpdateScript, _: *EngineContext) !void {}
};

//SCENE SCRIPTS
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "OnSceneStartScript";
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnSceneStartScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub const Scripttype: ScriptType = .SceneSceneStart;
    pub fn Deinit(_: *OnSceneStartScript, _: *EngineContext) !void {}
};

pub const SceneOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "SceneOnUpdateScript";
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == SceneOnUpdateScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub const Scripttype: ScriptType = .SceneOnUpdate;
    pub fn Deinit(_: *SceneOnUpdateScript, _: *EngineContext) !void {}
};

pub const InputPressedScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "InputPressedScript";
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == InputPressedScript) {
                break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
            }
        }
    };
    pub const Scripttype: ScriptType = .SceneInputPressed;
    pub fn Deinit(_: *InputPressedScript, _: *EngineContext) !void {}
};
