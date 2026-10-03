const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PreSolveInfo = @import("IM").PreSolveInfo;
const OnPreSolveScript = @This();

/// Function that gets executed every physics substep, before the solver stops or pushes apart this entity and
/// another solid one it is in contact with. Only for contacts where one of the two colliders has "Pre-Solve Events"
/// ticked. It runs in the middle of the physics step: read whatever you need and decide, but never create, delete
/// or move anything in here.
///     self:  the game object this script is on
///     other: the game object it is in contact with
///     info:  the contact as self sees it. info.mNormal points from self toward other, info.mSeparation is the gap
///            between them (negative while they overlap, and the contact can come before they touch), and
///            info.mSelfCollider / info.mOtherCollider are which colliders are in contact.
///            Set info.mEnabled = false and the two pass through each other on this substep. They don't count as
///            touching either, so a collision that began ends
/// return .Continue and the entity's other pre-solve scripts get this contact too
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Entity, other: *const Entity, info: *PreSolveInfo) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = other;

    //e.g. a one way platform, with this script on the platform: it only stops things landing on its top. Anything
    //coming from below or the side passes through, and so does anything still part way through it, which is deeper
    //in than the 0.01 the physics lets a resting body sink
    const lands_on_top = info.mNormal.y > 0.7; //pointing from the platform up toward the other, within about 45 degrees
    const above_top = info.mSeparation > -0.02;
    if (!lands_on_top or !above_top) info.mEnabled = false;

    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnPreSolve;
}
