const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;

//The script's variables go here, above its functions. Each one is shown under the script in the Scripts panel, where it
//can be set (an entity dragged onto an Entity), and saved with the object, and every object the script is on has its
//own. Each needs a default, and can be a f32, i32, u32, bool, enum, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player
//or GameContext. They are self's fields in the functions below, e.g. self.mSpeed
//mSpeed: f32 = 5.0,

//The functions the engine runs (its hooks) are named for when they run. A script can have any of the ones its object
//takes, e.g. OnUpdate and OnCollisionBegin together, and they all share the variables

/// Function that gets executed every frame after polling inputs and input events
/// return .Continue and it allows the event to be propegated to other layers/systems
/// return .Handled and it will stop at this layer
pub fn OnUpdate(self: *@This(), engine_context: *EngineContext, owner: Entity) !ScriptResult {
    _ = self;
    _ = engine_context;
    _ = owner;
    //your code goes here
    return .Continue;
}
