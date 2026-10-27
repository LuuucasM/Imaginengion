const std = @import("std");
const IM = @import("IM");
//this script: what each hook's Run takes as self
const Script = @This();

//Variables: shown in the Scripts panel and saved, one set per entity the script is on. Each needs a default
//mSpeed: f32 = 5.0,
//mTarget: IM.Entity = .uninit,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error
//
//Each hook lists what it touches: every component it gets from an object, its owner's or anything else's. Writes for
//the ones it changes (GetComponentMut), Reads for the rest (GetComponent), &.{} for none. A plain type is one on an
//entity; one on another kind of object goes through IM.In, e.g. IM.In(IM.SECS, IM.SceneComponents.SceneComponent) or
//IM.In(IM.GCECS, IM.GCComponents.AttribComponent). They are locked while the hook runs, so making or deleting things
//that have them waits until it is done, and a Debug build reports anything it touches but didn't list.

//every frame
pub const OnUpdate = struct {
    pub const Reads = &.{};
    pub const Writes = &.{};
    //e.g. pub const Writes = &.{IM.EntityComponents.TransformComponent};

    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult {
        _ = .{ self, engine_context, owner };
        return .Continue;
    }
};

//every key pressed
//pub const OnKeyPressed = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.KeyboardPressedEvent) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, event };
//        return .Continue;
//    }
//};

//every physics step, dt seconds long: apply forces here
//pub const OnPhysicsUpdate = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, dt: f32) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, dt };
//        return .Continue;
//    }
//};

//when it starts and stops touching other
//pub const OnCollisionBegin = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *const IM.CollisionInfo) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, other, info };
//        return .Continue;
//    }
//};
//pub const OnCollisionEnd = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *const IM.CollisionInfo) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, other, info };
//        return .Continue;
//    }
//};

//before the solver acts on a contact (needs "Pre-Solve Events" on a collider): set info.mEnabled = false to pass through
//pub const OnPreSolve = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *IM.PreSolveInfo) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, other, info };
//        return .Continue;
//    }
//};

//pointer (mouse) events on it or its children: enter, exit, press, click, drag, drop
//pub const OnPointerEvent = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.PointerEvent) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, event };
//        return .Continue;
//    }
//};

//UI events on it or its children: focus, text changed or submitted, popups, values changed
//pub const OnUIEvent = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.UIEvent) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, event };
//        return .Continue;
//    }
//};

//Game events: import one by its file name, send it with owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle
//it with a hook of any name whose Run's last parameter is it
//const ScoreEvent = @import("ScoreEvent");
//pub const OnScore = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Entity, event: *const ScoreEvent) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, event };
//        return .Continue;
//    }
//};
