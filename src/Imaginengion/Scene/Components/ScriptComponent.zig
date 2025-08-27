const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const SceneLayer = @import("../SceneLayer.zig");
const SceneType = @import("../SceneLayer.zig").Type;
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;
const AssetManager = @import("../../Assets/AssetManager.zig");

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i;
        }
    }
};

mFirst: SceneType = SceneLayer.NullScene,
mPrev: SceneType = SceneLayer.NullScene,
mNext: SceneType = SceneLayer.NullScene,
mParent: SceneType = SceneLayer.NullScene,
mScriptAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },

pub fn Deinit(_: *ScriptComponent) !void {}

pub fn GetName(self: ScriptComponent) []const u8 {
    _ = self;
    return "ScriptComponent";
}

pub fn GetInd(self: ScriptComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn jsonStringify(self: *const ScriptComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("FilePath");

    if (self.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
        const asset_file_data = try self.mScriptAssetHandle.GetAsset(FileMetaData);
        try jw.write(asset_file_data.mRelPath.items);
    } else {
        try jw.write("No Script Asset");
    }

    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!ScriptComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: ScriptComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "FilePath")) {
            const parsed_path = try std.json.parseFromTokenSource([]const u8, allocator, reader, options);

            result.mScriptAssetHandle = AssetManager.GetAssetHandleRef(parsed_path.value, .Prj) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        }
    }

    return result;
}
