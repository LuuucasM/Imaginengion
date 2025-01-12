pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const CircleRenderComponent = @import("Components/CircleRenderComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const SpriteRenderComponent = @import("Components/SpriteRenderComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const TriangleRenderComponent = @import("Components/TriangleRenderComponent.zig");

pub const ComponentsList = [_]type{
    CameraComponent,
    CircleRenderComponent,
    IDComponent,
    NameComponent,
    SpriteRenderComponent,
    TransformComponent,
    TriangleRenderComponent,
};

pub const EComponents = enum(usize) {
    CameraComponent = CameraComponent.Ind,
    CircleRenderComponent = CircleRenderComponent.Ind,
    IDComponent = IDComponent.Ind,
    NameComponent = NameComponent.Ind,
    SpriteRenderComponent = SpriteRenderComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    TriangleRenderComponent = TriangleRenderComponent.Ind,
};
