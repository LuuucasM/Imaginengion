const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const ComponentsList = @import("../../GameObjects/Components.zig").ComponentsList;
const AssetManager = @import("../../Assets/AssetManager.zig");
const TextComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TextComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn GetName(_: TextComponent) []const u8 {
    return "TextComponent";
}

pub fn GetInd(_: TextComponent) u32 {
    return @intCast(Ind);
}

mAllocator: std.mem.Allocator = undefined,
mText: std.ArrayList(u8) = .{},
mTextAssetHandle: ?AssetHandle = null,
mAtlasHandle: ?AssetHandle = null,

pub fn Deinit(self: *TextComponent) !void {
    if (self.mTextAssetHandle) |*asset_handle| {
        AssetManager.ReleaseAssetHandleRef(asset_handle);
    }
    if (self.mAtlasHandle) |*asset_handle| {
        AssetManager.ReleaseAssetHandleRef(asset_handle);
    }
    self.mText.deinit(self.mAllocator);
}

pub fn EditorRender(self: *TextComponent) !void {
    //TODO
}

pub fn jsonStringify(self: *const TextComponent, jw: anytype) !void {
    //TODO
}

pub fn jsonParse(allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!TextComponent {
    //TODO
}
