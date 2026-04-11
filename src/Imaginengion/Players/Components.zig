pub const RenderTargetComponent = @import("Components/RenderTargetComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const PossessComponent = @import("Components/PossessComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const UUIDComponent = @import("Components/UUIDComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");

pub const ComponentsList = [_]type{
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    PossessComponent,
    MicComponent,
    RenderTargetComponent,
};

pub const ScriptsList = [_]type{};

pub const EComponents = enum(u16) {
    RenderTargetComponent = RenderTargetComponent.Ind,
    MicComponent = MicComponent.Ind,
    PossessComponent = PossessComponent.Ind,
    NameComponent = NameComponent.Ind,
    UUIDComponent = UUIDComponent.Ind,
};
