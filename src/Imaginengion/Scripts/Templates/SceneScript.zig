const std = @import("std");
const IM = @import("IM");
//this script: what each hook's Run takes as self
const Script = @This();

//Variables: shown in the Scripts panel and saved, one set per scene the script is on. Each needs a default
//mBall: IM.Entity = .uninit,

//Hooks: take the // off any you want. Return .Continue to let the next script have its turn, .Handled to stop it here, .Warning when something didn't go as planned. An error (try) is logged and hands back .Error

//when the scene starts
pub fn OnSceneStart(self: *Script, engine_context: *IM.EngineContext, owner: IM.SceneLayer) !IM.ScriptResult {
    _ = .{ self, engine_context, owner };
    return .Continue;
}

//every frame
//pub fn OnUpdate(self: *Script, engine_context: *IM.EngineContext, owner: IM.SceneLayer) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner };
//    return .Continue;
//}

//every physics step, dt seconds long, before the scene's entities': apply forces here
//pub fn OnPhysicsUpdate(self: *Script, engine_context: *IM.EngineContext, owner: IM.SceneLayer, dt: f32) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, dt };
//    return .Continue;
//}

//Game events: import one by its file name, send it with owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle
//it with a function of any name whose last parameter is it
//const ScoreEvent = @import("ScoreEvent");
//pub fn OnScore(self: *Script, engine_context: *IM.EngineContext, owner: IM.SceneLayer, event: *const ScoreEvent) !IM.ScriptResult {
//    _ = .{ self, engine_context, owner, event };
//    return .Continue;
//}
