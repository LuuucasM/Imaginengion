const std = @import("std");
const IM = @import("IM");

//Variables: shown in the Scripts panel and saved, one set per entity the script is on. Each needs a default
//mSpeed: f32 = 5.0,
//mTarget: IM.Entity = .uninit,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error

//every frame
pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult {
    _ = .{ self, engine_context, owner };
    return .Continue;
}

//every key pressed
//pub fn OnKeyPressed(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.KeyboardPressedEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}

//every physics step, dt seconds long: apply forces here
//pub fn OnPhysicsUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, dt: f32) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, dt };
//    return .Continue;
//}

//when it starts and stops touching other
//pub fn OnCollisionBegin(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *const IM.CollisionInfo) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, other, info };
//    return .Continue;
//}
//pub fn OnCollisionEnd(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *const IM.CollisionInfo) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, other, info };
//    return .Continue;
//}

//before the solver acts on a contact (needs "Pre-Solve Events" on a collider): set info.mEnabled = false to pass through
//pub fn OnPreSolve(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, other: IM.Entity, info: *IM.PreSolveInfo) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, other, info };
//    return .Continue;
//}

//pointer (mouse) events on it or its children: enter, exit, press, click, drag, drop
//pub fn OnPointerEvent(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.PointerEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}

//UI events on it or its children: focus, text changed or submitted, popups, values changed
//pub fn OnUIEvent(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, event: *const IM.UIEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}

//Game events: import one by its file name, send it with owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle
//it with a function of any name whose last parameter is it
//const ScoreEvent = @import("ScoreEvent");
//pub fn OnScore(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity, event: *const ScoreEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}
