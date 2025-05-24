pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const CircleRenderComponent = @import("Components/CircleRenderComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const SceneIDComponent = @import("Components/SceneIDComponent.zig");
pub const SpriteRenderComponent = @import("Components/SpriteRenderComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnInputPressedScript = TagComponents.OnInputPressedScript;
pub const OnUpdateInputScript = TagComponents.OnUpdateInputScript;
pub const PrimaryCameraTag = TagComponents.PrimaryCameraTag;
pub const EditorCameraTag = TagComponents.EditorCameraTag;

pub const ComponentsList = [_]type{
    CameraComponent,
    CircleRenderComponent,
    IDComponent,
    NameComponent,
    SceneIDComponent,
    SpriteRenderComponent,
    TransformComponent,
    ScriptComponent,
    OnInputPressedScript,
    OnUpdateInputScript,
    PrimaryCameraTag,
    EditorCameraTag,
};

pub const EComponents = enum(usize) {
    CameraComponent = CameraComponent.Ind,
    CircleRenderComponent = CircleRenderComponent.Ind,
    IDComponent = IDComponent.Ind,
    NameComponent = NameComponent.Ind,
    SceneIDComponent = SceneIDComponent.Ind,
    SpriteRenderComponent = SpriteRenderComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressed = OnInputPressedScript.Ind,
    OnUpdateInput = OnUpdateInputScript.Ind,
    PrimaryCameraTag = PrimaryCameraTag.Ind,
    EditorCameraTag = EditorCameraTag.Ind,
};
