pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
const This = @This();

pub const ComponentsList = [_]type{
    AttribComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
};

pub const ComponentsPanelList = [_]type{
    AttribComponent,
    NameComponent,
    UUIDComponent,
};

pub const ScriptsList = [_]type{};

pub const EComponents = enum(u16) {
    RenderTargetComponent = AttribComponent.Ind,
    NameComponent = NameComponent.Ind,
    UUIDComponent = UUIDComponent.Ind,
};
