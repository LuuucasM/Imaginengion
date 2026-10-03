const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const CollisionInfo = @import("IM").CollisionInfo;
const OnCollisionBeginScript = @This();

/// Function that gets executed once when this entity's collider starts touching another one.
/// It runs right after the physics step, for every collision this entity is in: check what was hit
/// in here, the way a key pressed script checks which key it was given.
///     self:  the game object this script is on
///     other: the game object it hit
///     info:  the contact as self sees it. info.mNormal points from self toward other,
///            info.mIsTrigger is true when the two passed through each other instead of bouncing, and
///            info.mSelfCollider / info.mOtherCollider are which colliders touched: the game object itself,
///            or one of its convenience children when its colliders are on those (e.g. a head and feet)
/// return .Continue and the entity's other collision scripts get this collision too
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Entity, other: *const Entity, info: *const CollisionInfo) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = other;

    //e.g. only carry on for things in collision category 1. The collider rather than the game object, which may
    //keep its colliders on its children
    const other_collider = info.mOtherCollider.GetComponent(EntityComponents.ColliderComponent) orelse return .Continue;
    if (!other_collider.mCollisionFilter.CategoryMask.isSet(1)) return .Continue;

    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnCollisionBegin;
}
