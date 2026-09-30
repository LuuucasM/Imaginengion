const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptType = @import("IM").ScriptType;
const CollisionInfo = @import("IM").CollisionInfo;
const OnCollisionBeginScript = @This();

/// Function that gets executed once when this entity's collider starts touching another one.
/// It runs right after the physics step, for every collision this entity is in: check what was hit
/// in here, the way a key pressed script checks which key it was given.
///     self:  the entity this script is on
///     other: the entity it hit
///     info:  the contact as self sees it. info.mNormal points from self toward other, and
///            info.mIsTrigger is true when the two passed through each other instead of bouncing
/// if this function returns true the entity's other collision scripts get this collision too
/// if it returns false it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Entity, other: *const Entity, info: *const CollisionInfo) callconv(.c) bool {
    _ = engine_context;
    _ = self;
    _ = info;

    //e.g. only carry on for things in collision category 1
    const other_collider = other.GetComponent(EntityComponents.ColliderComponent) orelse return true;
    if (!other_collider.mCollisionFilter.CategoryMask.isSet(1)) return true;

    //your code goes here
    return true;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnCollisionBegin;
}
