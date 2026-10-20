const std = @import("std");
const IM = @import("IM");

//What this script touches: every component it gets from an object (GetComponent), its owner's or anything else's. Both are
//needed, &.{} for none. They are locked while it runs, so making or deleting things that have them waits until it is
//done, and a Debug build stops on anything it touches but didn't list. Writes for the ones it changes, Reads for the rest
pub const Reads = &.{};
pub const Writes = &.{};
//e.g. pub const Writes = &.{IM.EntityComponents.TransformComponent};

//Variables: shown in the Scripts panel and saved, one set per player the script is on. Each needs a default
//mMoveSpeed: f32 = 10.0,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error

//every frame
pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Player) !IM.ScriptResult {
    _ = .{ self, engine_context, owner };
    return .Continue;
}

//every key pressed that no entity's OnKeyPressed handled
//pub fn OnKeyPressed(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Player, event: *const IM.KeyboardPressedEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}

//Game events: import one by its file name, send it with owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle
//it with a function of any name whose last parameter is it
//const ScoreEvent = @import("ScoreEvent");
//pub fn OnScore(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Player, event: *const ScoreEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}
