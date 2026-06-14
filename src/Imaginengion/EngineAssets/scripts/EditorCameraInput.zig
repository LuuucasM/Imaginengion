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
pub export fn Run(engine_context: *EngineContext, allocator: *const std.mem.Allocator, self: *Entity) callconv(.c) bool {
    _ = allocator;
    const input_context = &engine_context.mInputManager;
    if (input_context.IsKeyPressed(.LALT) == true) {
        const PanSpeed = 0.015;
        const RotateSpeed = 0.08;
        const ZoomSpeed = 0.03;

        const mouse_delta = input_context.GetMousePositionDelta();

        const transform_component = self.GetComponent(TransformComponent).?;
        var translation = transform_component.Translation;
        var rotation = transform_component.Rotation;

        if (input_context.IsMousePressed(.BUTTON_MIDDLE) == true) {
            const right_dir = rotation.GetRightDir();
            const up_dir = rotation.GetUpDir();
            translation.SubEqVec(right_dir.MulScalar(mouse_delta.x * PanSpeed));
            translation.AddEqVec(up_dir.MulScalar(mouse_delta.y * PanSpeed));
            transform_component.Translation = translation;
        } else if (input_context.IsMousePressed(.BUTTON_LEFT) == true) {
            //const up_dir = GetUpDirection(rotation); //yaw
            const up_dir = Vec3(f32){ .x = 0.0, .y = 1.0, .z = 0.0 }; //yaw
            const right_dir = rotation.GetRightDir(); //pitch

            const yaw = Quat(f32).FromAxisAngle(up_dir, -mouse_delta.x * RotateSpeed);
            const pitch = Quat(f32).FromAxisAngle(right_dir, -mouse_delta.y * RotateSpeed);
            rotation = rotation.MulQuat(yaw).MulQuat(pitch);
            transform_component.Rotation = rotation;
        } else if (input_context.IsMousePressed(.BUTTON_RIGHT) == true) {
            const forward_dir = rotation.GetForwardDir();
            translation.AddEqVec(forward_dir.MulScalar(mouse_delta.y * ZoomSpeed));
            transform_component.Translation = translation;
        }
    }

    return true;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}
