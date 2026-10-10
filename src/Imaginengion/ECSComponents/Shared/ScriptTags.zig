const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ScriptType = @import("../Asset/ScriptAsset.zig").ScriptType;
const ScriptResult = @import("../Asset/ScriptAsset.zig").ScriptResult;
const SceneLayer = @import("../../ECSObjects/Scene.zig");

const WindowEventData = @import("../../Events/WindowEventData.zig");
const KeyboardPressedEvent = WindowEventData.KeyboardPressedEvent;

const CollisionInfo = @import("../../Physics/Collisions.zig").CollisionInfo;
const PreSolveInfo = @import("../../Physics/Collisions.zig").PreSolveInfo;
const PointerEvent = @import("../../Events/PointerEventData.zig").PointerEvent;
const UIEvent = @import("../../Events/UIEventData.zig").UIEvent;

//ENTITY SCRIPTS
pub const OnKeyPressedScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity, *const KeyboardPressedEvent) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnKeyPressedScript";
    pub const Scripttype: ScriptType = .EntityInputPressed;
    pub fn Deinit(_: *OnKeyPressedScript, _: *EngineContext) void {}
};

pub const EntityOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*const EngineContext, *const Entity) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnUpdate;
    pub fn Deinit(_: *EntityOnUpdateScript, _: *EngineContext) void {}
};

/// Runs once when the owner's collider starts touching another one (see CollisionBeginEvent), whatever
/// it touched: like a key pressed script being handed every key, the script itself checks what it hit
pub const OnCollisionBeginScript = struct {
    //engine context, the script's owner, the entity it hit, and the contact as the owner sees it
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, *const Entity, *const CollisionInfo) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnCollisionBeginScript";
    pub const Scripttype: ScriptType = .EntityOnCollisionBegin;
    pub fn Deinit(_: *OnCollisionBeginScript, _: *EngineContext) void {}
};

/// Runs once when the owner's collider stops touching another one (see CollisionEndEvent), the counterpart of
/// OnCollisionBeginScript: every collision that began ends once. Handed the same CollisionInfo, with a zero normal.
/// It still runs when the other entity was deleted, which ends the collision too, so check other.IsActive() before
/// reading anything off it. An owner that was deleted is not run at all
pub const OnCollisionEndScript = struct {
    //engine context, the script's owner, the entity it was touching, and the contact as the owner saw it
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, *const Entity, *const CollisionInfo) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnCollisionEndScript";
    pub const Scripttype: ScriptType = .EntityOnCollisionEnd;
    pub fn Deinit(_: *OnCollisionEndScript, _: *EngineContext) void {}
};

/// Runs from the middle of the physics step, before the solver acts on a solid contact of the owner's, every substep
/// the contact is there (see PreSolveEvent). Only for contacts where one of the two colliders has mPreSolveEvents on.
/// Set info.mEnabled to false to have the two pass through each other on this substep, e.g. a one way platform.
/// The step's contact lists are live while it runs: read the world and decide, never create, delete or move anything
pub const OnPreSolveScript = struct {
    //engine context, the script's owner, the entity in contact with it, and the contact as the owner sees it
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, *const Entity, *PreSolveInfo) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnPreSolveScript";
    pub const Scripttype: ScriptType = .EntityOnPreSolve;
    pub fn Deinit(_: *OnPreSolveScript, _: *EngineContext) void {}
};

/// Runs at the start of every physics step, at the physics' own fixed rate rather than once a frame (see
/// PhysicsEventData.StepBeginEvent): the place for anything the physics should feel, like forces. A force
/// applied here pushes for the whole step and is let go of after it
pub const EntityOnPhysicsUpdateScript = struct {
    //engine context, the script's owner, and the length of the step in seconds, the same every step
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, f32) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnPhysicsUpdateScript";
    pub const Scripttype: ScriptType = .EntityOnPhysicsUpdate;
    pub fn Deinit(_: *EntityOnPhysicsUpdateScript, _: *EngineContext) void {}
};

/// Runs for every pointer event sent to the owner (see Events/PointerEventData.zig): entered, exited, pressed,
/// released, clicked, dragged, dropped on. Only the owner's own events reach it, so it never checks who an event is
/// for; like a key pressed script being handed every key, it checks which event it got. The pointer's events go to what it is over and then to each thing that is inside of, so a script on a
/// panel hears clicks on its rows too, and the event's mTarget is what was actually under the pointer. Returning
/// .Handled keeps a press, click, drag or drop from going on to the owner's parents (an enter or exit is each one's own)
pub const OnPointerEventScript = struct {
    //engine context, the script's owner, and the event
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, *const PointerEvent) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnPointerEventScript";
    pub const Scripttype: ScriptType = .EntityOnPointerEvent;
    pub fn Deinit(_: *OnPointerEventScript, _: *EngineContext) void {}
};

/// OnPointerEventScript for the UI's events (see Events/UIEventData.zig): a text input getting or losing the keyboard,
/// its text changing or being submitted, a popup opening or closing. Run right after the pointer's events
pub const OnUIEventScript = struct {
    //engine context, the script's owner, and the event
    pub const RunFuncSig = *const fn (*EngineContext, *const Entity, *const UIEvent) callconv(.c) ScriptResult;
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnUIEventScript";
    pub const Scripttype: ScriptType = .EntityOnUIEvent;
    pub fn Deinit(_: *OnUIEventScript, _: *EngineContext) void {}
};

//SCENE SCRIPTS
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) ScriptResult;
    pub const Name: []const u8 = "OnSceneStartScript";
    pub const Scripttype: ScriptType = .SceneSceneStart;
    pub fn Deinit(_: *OnSceneStartScript, _: *EngineContext) void {}
};

pub const SceneOnUpdateScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) ScriptResult;
    pub const Name: []const u8 = "SceneOnUpdateScript";
    pub const Scripttype: ScriptType = .SceneOnUpdate;
    pub fn Deinit(_: *SceneOnUpdateScript, _: *EngineContext) void {}
};

/// EntityOnPhysicsUpdateScript for a scene, e.g. a rule that pushes on every body in it. A scene's run before its
/// entities' on each step
pub const SceneOnPhysicsUpdateScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer, f32) callconv(.c) ScriptResult;
    pub const Name: []const u8 = "SceneOnPhysicsUpdateScript";
    pub const Scripttype: ScriptType = .SceneOnPhysicsUpdate;
    pub fn Deinit(_: *SceneOnPhysicsUpdateScript, _: *EngineContext) void {}
};

pub const InputPressedScript = struct {
    pub const RunFuncSig = *const fn (*EngineContext, *const SceneLayer) callconv(.c) ScriptResult;
    pub const Name: []const u8 = "InputPressedScript";
    pub const Scripttype: ScriptType = .SceneInputPressed;
    pub fn Deinit(_: *InputPressedScript, _: *EngineContext) void {}
};
