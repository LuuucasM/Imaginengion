const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptResult = @import("IM").ScriptResult;
const CollisionInfo = @import("IM").CollisionInfo;

//The script's variables go here, above its functions. Each one is shown under the script in the Scripts panel, where it
//can be set (an entity dragged onto an Entity), and saved with the object, and every object the script is on has its
//own. Each needs a default, and can be a f32, i32, u32, bool, enum, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player
//or GameContext. They are self's fields in the functions below, e.g. self.mSpeed
//mSpeed: f32 = 5.0,

//The functions the engine runs (its hooks) are named for when they run. A script can have any of the ones its object
//takes, e.g. OnUpdate and OnCollisionBegin together, and they all share the variables

/// Function that gets executed once when this entity's collider stops touching another one, for every collision
/// that began (see OnCollisionBeginTemplate). It runs right after the physics step.
///     owner: the game object this script is on
///     other: the game object it was touching. A collision also ends when other is deleted, so check
///            other.IsActive() before reading anything off it
///     info:  the contact as owner saw it. info.mNormal is zero, the two are apart. info.mIsTrigger is true when
///            the two were passing through each other, and info.mSelfCollider / info.mOtherCollider are which
///            colliders were touching (these can be deleted too)
/// return .Continue and the entity's other collision end scripts get this collision too
/// return .Handled and it will stop at this script
pub fn OnCollisionEnd(self: *@This(), engine_context: *EngineContext, owner: Entity, other: Entity, info: *const CollisionInfo) !ScriptResult {
    _ = self;
    _ = engine_context;
    _ = owner;
    _ = info;

    //the collision has ended whether or not other still exists (e.g. a count of what owner is standing on goes
    //down either way), only reading other's components needs it to
    if (other.IsActive()) {
        //code that reads other goes here
    }

    //your code goes here
    return .Continue;
}
