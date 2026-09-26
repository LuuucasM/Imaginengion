const ListInd = @import("../ECS/Components.zig").ListInd;
pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");
const This = @This();

pub const ComponentsList = [_]type{
    AttribComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
    TmplRefComponent,
};

pub const ComponentsPanelList = [_]type{
    AttribComponent,
    NameComponent,
    UUIDComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
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
    AttribComponent = ListInd(&ComponentsList, AttribComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
};
