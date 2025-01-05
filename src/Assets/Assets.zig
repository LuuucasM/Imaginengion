pub const AssetMetaData = @import("./Assets/AssetMetaData.zig");
pub const FileMetaData = @import("./Assets/FileMetaData.zig");
pub const IDComponent = @import("./Assets/IDComponent.zig");
pub const Texture2D = @import("./Assets/Texture2D.zig");

pub const AssetsList = [_]type{
    AssetMetaData,
    FileMetaData,
    IDComponent,
    Texture2D,
};

pub const EAssets = enum(usize) {
    AssetMetaData = AssetMetaData.Ind,
    FileMetaData = FileMetaData.Ind,
    IDComponent = IDComponent.Ind,
    Texture2D = Texture2D.Ind,
};
