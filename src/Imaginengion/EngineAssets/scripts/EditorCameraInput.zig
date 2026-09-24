const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const Vec3 = @import("IM").Vec3;
const Quat = @import("IM").Quat;
const Vec2 = @import("IM").Vec2;
const ScriptType = @import("IM").ScriptType;
const TransformComponent = @import("IM").EntityComponents.TransformComponent;
const OnUpdateTemplate = @This();

/// Function that gets executed every frame after polling inputs and input events
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const Entity) callconv(.c) bool {
    const input_context = &engine_context.mInputManager;
    if (input_context.IsKeyPressed(.LALT) == true) {
        //all per pixel of mouse movement. pan and zoom are world units, rotate is radians
        //(0.004 rad is about 0.23 degrees, so a 400px drag turns roughly 90 degrees)
        const PanSpeed = 0.025;
        const RotateSpeed = 0.004;
        const ZoomSpeed = 0.05;

        const mouse_delta = input_context.GetMousePositionDelta();

        const transform_component = self.GetComponent(TransformComponent).?;
        var translation = transform_component.GetTranslation();
        var rotation = transform_component.GetRotation();

        if (input_context.IsMousePressed(.BUTTON_MIDDLE) == true) {
            const right_dir = rotation.GetRightDir();
            const up_dir = rotation.GetUpDir();
            translation.SubEqVec(right_dir.MulScalar(mouse_delta.x * PanSpeed));
            translation.AddEqVec(up_dir.MulScalar(mouse_delta.y * PanSpeed));
            self.SetTranslation(engine_context, translation) catch return false;
        } else if (input_context.IsMousePressed(.BUTTON_LEFT) == true) {
            //yaw turns around the world up axis so the horizon stays level, so it multiplies on
            //the left. pitch turns around the camera's own right axis, so it multiplies on the
            //right, where the axis is read in the camera's local space.
            const world_up = Vec3(f32){ .x = 0.0, .y = 1.0, .z = 0.0 };
            const local_right = Vec3(f32){ .x = 1.0, .y = 0.0, .z = 0.0 };

            const yaw = Quat(f32).FromAxisAngle(world_up, -mouse_delta.x * RotateSpeed);
            const pitch = Quat(f32).FromAxisAngle(local_right, -mouse_delta.y * RotateSpeed);
            rotation = yaw.MulQuat(rotation).MulQuat(pitch);
            self.SetRotation(engine_context, rotation) catch return false;
        } else if (input_context.IsMousePressed(.BUTTON_RIGHT) == true) {
            const forward_dir = rotation.GetForwardDir();
            translation.AddEqVec(forward_dir.MulScalar(mouse_delta.y * ZoomSpeed));
            self.SetTranslation(engine_context, translation) catch return false;
        }
    }

    return true;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}
