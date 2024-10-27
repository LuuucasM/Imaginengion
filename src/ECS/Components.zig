pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const Render2DComponent = @import("Components/Render2DComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");

pub const ComponentsList = [_]type{
    IDComponent,
    NameComponent,
    TransformComponent,
    Render2DComponent,
};

pub const EComponents = enum(usize) {
    IDComponent = IDComponent.Ind,
    NameComponent = NameComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    Render2DComponent = Render2DComponent.Ind,
};
