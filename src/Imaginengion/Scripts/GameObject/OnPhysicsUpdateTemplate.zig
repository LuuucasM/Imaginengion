const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const EntityComponents = @import("IM").EntityComponents;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const OnPhysicsUpdateScript = @This();

/// Function that gets executed at the start of every physics step: at the physics' own fixed rate, not once a
/// frame, so a frame can run it more than once or not at all. The place for anything the physics should feel.
/// A force applied here (RigidBodyComponent.ApplyForce) pushes for this whole step and is let go of after it,
/// so apply it again every step for as long as it should keep pushing. For example, a jetpack:
///
///     const rigid_body = self.GetComponent(EntityComponents.RigidBodyComponent) orelse return .Continue;
///     if (engine_context.mInputManager.IsKeyPressed(.SPACE)) {
///         rigid_body.ApplyForce(.{ .x = 0, .y = 20, .z = 0 });
///     }
///
///     self: the entity this script is on
///     dt:   the length of the step in seconds, the same every step
/// return .Continue and the other physics update scripts run after it
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Entity, dt: f32) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = dt;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnPhysicsUpdate;
}
