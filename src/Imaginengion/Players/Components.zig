pub const RenderTargetComponent = @import("Components/RenderTargetComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const PossessComponent = @import("Components/PossessComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");

pub const ComponentsList = [_]type{
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    NameComponent,
};

pub const EComponents = enum(u16) {
    RenderTargetComponent = RenderTargetComponent.Ind,
    MicComponent = MicComponent.Ind,
    PossessComponent = PossessComponent.Ind,
    NameComponent = NameComponent.Ind,
};
