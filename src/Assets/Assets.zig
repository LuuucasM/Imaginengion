pub const Texture2D = @import("./Assets/Textures/Texture2D.zig");

pub const AssetsList = [_]type{
    Texture2D,
};

pub const EAssets = enum(usize) {
    Texture2D = Texture2D.Ind,
};
