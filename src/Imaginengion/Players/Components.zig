pub const LensComponent = @import("Components/LensComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const PossessComponent = @import("Components/PossessComponent.zig");

pub const ComponentsList = [_]type{
    LensComponent,
    MicComponent,
    PossessComponent,
};

pub const EComponents = enum(u16) {
    LensComponent = LensComponent.Ind,
    MicComponent = MicComponent.Ind,
    PossessComponent = PossessComponent.Ind,
};
