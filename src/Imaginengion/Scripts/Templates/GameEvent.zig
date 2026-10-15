const IM = @import("IM");

//A game event: data your scripts send each other. Import it by this file's name, @import("ScoreEvent"), send it with
//owner.GetWorld().Emit(engine_context, ScoreEvent{}), and handle it with a function whose last parameter is it

//when it is handled: .AfterPhysics or .AfterUpdate
pub const Phase: IM.GamePhase = .AfterUpdate;

//What it carries: plain data (numbers, bools, enums, vectors, Entity...), each with a default
//mPoints: u32 = 0,
