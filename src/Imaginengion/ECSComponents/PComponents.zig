const ListInd = @import("../ECS/Components.zig").ListInd;
pub const RenderTargetComponent = @import("Shared/RenderTargetComponent.zig");
pub const MicComponent = @import("Player/MicComponent.zig");
pub const PossessComponent = @import("Player/PossessComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");

pub const ComponentsList = [_]type{
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
    TmplRefComponent,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    PossessComponent,
    MicComponent,
    RenderTargetComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    TmplRefComponent,
};

/// What a linked copy keeps of its own when it is stripped down (see ECSObject.Core.Strip), everything
/// else in SerializeList it gets from its template
pub const ShellList = [_]type{
    UUIDComponent,
    NameComponent,
    TmplRefComponent,
};

pub const ScriptsList = [_]type{};

pub const EComponents = enum(u16) {
    RenderTargetComponent = ListInd(&ComponentsList, RenderTargetComponent),
    MicComponent = ListInd(&ComponentsList, MicComponent),
    PossessComponent = ListInd(&ComponentsList, PossessComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
};
