const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const CollisionInfo = @import("IM").CollisionInfo;
const OnCollisionEndScript = @This();

/// Function that gets executed once when this entity's collider stops touching another one, for every collision
/// that began (see OnCollisionBeginTemplate). It runs right after the physics step.
///     self:  the game object this script is on
///     other: the game object it was touching. A collision also ends when other is deleted, so check
///            other.IsActive() before reading anything off it
///     info:  the contact as self saw it. info.mNormal is zero, the two are apart. info.mIsTrigger is true when
///            the two were passing through each other, and info.mSelfCollider / info.mOtherCollider are which
///            colliders were touching (these can be deleted too)
/// return .Continue and the entity's other collision end scripts get this collision too
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Entity, other: *const Entity, info: *const CollisionInfo) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = info;

    //the collision has ended whether or not other still exists (e.g. a count of what self is standing on goes
    //down either way), only reading other's components needs it to
    if (other.IsActive()) {
        //code that reads other goes here
    }

    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnCollisionEnd;
}
