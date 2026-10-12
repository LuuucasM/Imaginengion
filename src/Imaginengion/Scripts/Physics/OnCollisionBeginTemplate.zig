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

/// Function that gets executed once when this entity's collider starts touching another one.
/// It runs right after the physics step, for every collision this entity is in: check what was hit
/// in here, the way a key pressed script checks which key it was given.
///     owner: the game object this script is on
///     other: the game object it hit
///     info:  the contact as owner sees it. info.mNormal points from owner toward other,
///            info.mIsTrigger is true when the two passed through each other instead of bouncing, and
///            info.mSelfCollider / info.mOtherCollider are which colliders touched: the game object itself,
///            or one of its convenience children when its colliders are on those (e.g. a head and feet)
/// return .Continue and the entity's other collision scripts get this collision too
/// return .Handled and it will stop at this script
pub fn OnCollisionBegin(self: *@This(), engine_context: *EngineContext, owner: Entity, other: Entity, info: *const CollisionInfo) !ScriptResult {
    _ = self;
    _ = engine_context;
    _ = owner;
    _ = other;

    //e.g. only carry on for things in collision category 1. The collider rather than the game object, which may
    //keep its colliders on its children
    const other_collider = info.mOtherCollider.GetComponent(EntityComponents.ColliderComponent) orelse return .Continue;
    if (!other_collider.mCollisionFilter.CategoryMask.isSet(1)) return .Continue;

    //your code goes here
    return .Continue;
}
