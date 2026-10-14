const IM = @import("IM");

//A game event: something your scripts tell each other about, like a goal being scored. It isn't run itself, it is
//only data. A script imports it by this file's name, wherever it is in the project:
//  const ScoreEvent = @import("ScoreEvent");
//sends it through the world it is in:
//  try owner.GetWorld().Emit(engine_context, ScoreEvent{ .mPoints = 1 });
//and handles it with a function of any name whose last parameter is it. Every script in the world with one gets it:
//  pub fn OnScore(self: *@This(), engine_context: *IM.EngineContext, owner: IM.GameContext, event: *const ScoreEvent) !IM.ScriptResult
//Returning .Handled from a handler keeps the event from the handlers after it.

/// When the event is handled: .AfterPhysics (right after the physics step, before every OnUpdate) or .AfterUpdate
/// (after every OnUpdate, before the frame is drawn, so what reacts to it shows straight away)
pub const Phase: IM.GamePhase = .AfterUpdate;

//What the event carries goes here. It is plain data: numbers, bools, enums, vectors, Entity, SceneLayer, Player,
//GameContext, and structs and arrays of those. Each needs a default, e.g.
//mPoints: u32 = 0,
//mScorer: IM.Entity = .uninit,
