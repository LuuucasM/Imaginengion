const ListInd = @import("../ECS/Components.zig").ListInd;
pub const RenderTargetComponent = @import("Shared/RenderTargetComponent.zig");
pub const MicComponent = @import("Player/MicComponent.zig");
pub const PossessComponent = @import("Player/PossessComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");

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
    RenderTargetComponent = ListInd(&ComponentsList, RenderTargetComponent),
    MicComponent = ListInd(&ComponentsList, MicComponent),
    PossessComponent = ListInd(&ComponentsList, PossessComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
};
