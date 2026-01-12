const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const LinAlg = @import("IM").LinAlg;
const Vec3f32 = @import("IM").Vec3f32;
const Quatf32 = @import("IM").Quatf32;
const Vec2f32 = @import("IM").Vec2f32;
const ScriptType = @import("IM").ScriptType;
const TransformComponent = @import("IM").EntityComponents.TransformComponent;
const OnUpdateInputTemplate = @This();

/// Function that gets executed every frame after polling inputs and input events
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, allocator: *const std.mem.Allocator, self: *Entity) callconv(.c) bool {
    _ = allocator;
    var input_context = engine_context.mInputManager;
    if (input_context.IsInputPressed(.LeftAlt) == true) {
        const PanSpeed = 0.015;
        const RotateSpeed = 0.08;
        const ZoomSpeed = 0.03;

        const mouse_delta = input_context.GetMousePositionDelta();

        const transform_component = self.GetComponent(TransformComponent).?;
        var translation = transform_component.Translation;
        var rotation = transform_component.Rotation;

        if (input_context.IsInputPressed(.MouseButtonMiddle) == true) {
            const right_dir = GetRightDirection(rotation);
            const up_dir = GetUpDirection(rotation);
            translation = translation - right_dir * @as(Vec3f32, @splat(mouse_delta[0] * PanSpeed)) + (up_dir * @as(Vec3f32, @splat(mouse_delta[1] * PanSpeed)));
            transform_component.SetTranslation(translation);
        } else if (input_context.IsInputPressed(.MouseButtonLeft) == true) {
            //const up_dir = GetUpDirection(rotation); //yaw
            const up_dir = Vec3f32{ 0.0, 1.0, 0.0 }; //yaw
            const right_dir = GetRightDirection(rotation); //pitch

            const yaw = LinAlg.QuatAngleAxis(-mouse_delta[0] * RotateSpeed, up_dir);
            const pitch = LinAlg.QuatAngleAxis(-mouse_delta[1] * RotateSpeed, right_dir);
            rotation = LinAlg.QuatMulQuat(LinAlg.QuatMulQuat(yaw, rotation), pitch);
            transform_component.SetRotation(rotation);
        } else if (input_context.IsInputPressed(.MouseButtonRight) == true) {
            const forward_dir = GetForwardDirection(rotation);
            translation += forward_dir * @as(Vec3f32, @splat(mouse_delta[1] * ZoomSpeed));
            transform_component.SetTranslation(translation);
        }
    }

    return true;
}

fn GetRightDirection(rotation: Quatf32) Vec3f32 {
    return LinAlg.RotateVec3Quat(rotation, Vec3f32{ 1.0, 0.0, 0.0 });
}
fn GetUpDirection(rotation: Quatf32) Vec3f32 {
    return LinAlg.RotateVec3Quat(rotation, Vec3f32{ 0.0, 1.0, 0.0 });
}
fn GetForwardDirection(rotation: Quatf32) Vec3f32 {
    return LinAlg.RotateVec3Quat(rotation, Vec3f32{ 0.0, 0.0, -1.0 });
}

pub export fn EditorRender() callconv(.c) void {}

//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}
