const std = @import("std");
const IM = @import("IM");
//this script: what each hook's Run takes as self
const Script = @This();

//Variables: shown in the Scripts panel and saved, one set per player the script is on. Each needs a default
//mMoveSpeed: f32 = 10.0,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error
//
//Each hook lists what it touches: every component it gets from an object, its owner's or anything else's. Writes for
//the ones it changes (GetComponentMut), Reads for the rest (GetComponent), &.{} for none. A plain type is one on a
//player; one on another kind of object goes through IM.In, e.g. IM.In(IM.EECS, IM.EntityComponents.TransformComponent)
//for the entity it possesses. They are locked while the hook runs, so making or deleting things that have them waits
//until it is done, and a Debug build reports anything it touches but didn't list.

//every frame
pub const OnUpdate = struct {
    pub const Reads = &.{};
    pub const Writes = &.{};

    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Player) !IM.ScriptResult {
        _ = .{ self, engine_context, owner };
        return .Continue;
    }
};

//every key pressed that no entity's OnKeyPressed handled
//pub const OnKeyPressed = struct {
//    pub const Reads = &.{};
//    pub const Writes = &.{};
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Player, event: *const IM.KeyboardPressedEvent) !IM.ScriptResult {
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
//    pub fn Run(self: *Script, engine_context: *IM.EngineContext, owner: IM.Player, event: *const ScoreEvent) !IM.ScriptResult {
//        _ = .{ self, engine_context, owner, event };
//        return .Continue;
//    }
//};
