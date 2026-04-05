const AttribComponent = @import("Components/AttribComponent.zig");

pub const ComponentsList = [_]type{
    AttribComponent,
};

pub const EComponents = enum(u16) {
    RenderTargetComponent = AttribComponent.Ind,
};
