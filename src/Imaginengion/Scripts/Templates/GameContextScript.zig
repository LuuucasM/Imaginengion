const std = @import("std");
const IM = @import("IM");

//Variables: shown in the Scripts panel and saved, one set per game context the script is on. Each needs a default
//mPlayerScore: u32 = 0,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error

//once, when the game starts
pub fn OnGameStart(self: *@This(), engine_context: *IM.EngineContext, owner: IM.GameContext) !IM.ScriptResult {
    _ = .{ self, engine_context, owner };
    return .Continue;
}

//every frame, before every other OnUpdate
//pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.GameContext) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner };
//    return .Continue;
//}

//Game events: import one by its file name, send it with owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle
//it with a function of any name whose last parameter is it
//const ScoreEvent = @import("ScoreEvent");
//pub fn OnScore(self: *@This(), engine_context: *IM.EngineContext, owner: IM.GameContext, event: *const ScoreEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}
