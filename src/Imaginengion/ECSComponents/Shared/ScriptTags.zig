const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ScriptType = @import("../Asset/ScriptAsset.zig").ScriptType;
const SceneLayer = @import("../../ECSObjects/Scene.zig");

const WindowEventData = @import("../../Events/WindowEventData.zig");
const KeyboardPressedEvent = WindowEventData.KeyboardPressedEvent;

//ENTITY SCRIPTS
pub const OnKeyPressedScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity, *const KeyboardPressedEvent) callconv(.c) bool;
    bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnKeyPressedScript";
    pub const Scripttype: ScriptType = .EntityInputPressed;
    pub fn Deinit(_: *OnKeyPressedScript, _: *EngineContext) void {}
};

pub const EntityOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity) callconv(.c) bool;
    bit: u1 = 0,
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnUpdate;
    pub fn Deinit(_: *EntityOnUpdateScript, _: *EngineContext) void {}
};

//SCENE SCRIPTS
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "OnSceneStartScript";
    pub const Scripttype: ScriptType = .SceneSceneStart;
    pub fn Deinit(_: *OnSceneStartScript, _: *EngineContext) void {}
};

pub const SceneOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "SceneOnUpdateScript";
    pub const Scripttype: ScriptType = .SceneOnUpdate;
    pub fn Deinit(_: *SceneOnUpdateScript, _: *EngineContext) void {}
};

pub const InputPressedScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) bool;
    bit: u1 = 0,
    pub const Name: []const u8 = "InputPressedScript";
    pub const Scripttype: ScriptType = .SceneInputPressed;
    pub fn Deinit(_: *InputPressedScript, _: *EngineContext) void {}
};
