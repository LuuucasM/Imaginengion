const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const SceneLayer = @import("IM").SceneLayer;
const ScriptResult = @import("IM").ScriptResult;

//The script's variables go here, above its functions. Each one is shown under the script in the Scripts panel, where it
//can be set (an entity dragged onto an Entity), and saved with the object, and every object the script is on has its
//own. Each needs a default, and can be a f32, i32, u32, bool, enum, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player
//or GameContext. They are self's fields in the functions below, e.g. self.mSpeed
//mSpeed: f32 = 5.0,

//The functions the engine runs (its hooks) are named for when they run. A script can have any of the ones its object
//takes, e.g. OnUpdate and OnCollisionBegin together, and they all share the variables

/// Function that gets executed at the start of every physics step: at the physics' own fixed rate, not once a
/// frame. A scene's physics update scripts run before its entities' on each step, so this is the place for rules
/// of the scene that the physics should feel, e.g. a push on every body in it.
/// A force applied here pushes for this whole step and is let go of after it.
///     owner: the scene this script is on
///     dt:    the length of the step in seconds, the same every step
/// return .Continue and the other physics update scripts run after it
/// return .Handled and it will stop at this script
pub fn OnPhysicsUpdate(self: *@This(), engine_context: *EngineContext, owner: SceneLayer, dt: f32) !ScriptResult {
    _ = self;
    _ = engine_context;
    _ = owner;
    _ = dt;
    //your code goes here
    return .Continue;
}
