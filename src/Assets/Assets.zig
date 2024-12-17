pub const Texture2D = @import("./Assets/Texture2D.zig");
pub const IDComponent = @import("./Assets/IDComponent.zig");

pub const AssetsList = [_]type{
    Texture2D,
    IDComponent,
};

pub const EAssets = enum(usize) {
    Texture2D = Texture2D.Ind,
    IDComponent = IDComponent.Ind,
};
