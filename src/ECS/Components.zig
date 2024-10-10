pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const Render2DComponent = @import("Components/Render2DComponent.zig");
pub const SceneIDComponent = @import("Components/SceneIDComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");

pub const ComponentsList = [_]type{
    IDComponent,
    NameComponent,
    Render2DComponent,
    SceneIDComponent,
    TransformComponent,
};
