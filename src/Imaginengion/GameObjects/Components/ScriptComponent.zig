const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const Entity = @import("../../GameObjects/Entity.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

const AssetManager = @import("../../Assets/AssetManager.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mScriptAssetHandle: ?AssetHandle = null,

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = false;

pub fn Deinit(self: *ScriptComponent) !void {
    if (self.mScriptAssetHandle) |*asset_handle| {
        AssetManager.ReleaseAssetHandleRef(asset_handle);
    }
}

pub fn GetName(self: ScriptComponent) []const u8 {
    _ = self;
    return "ScriptComponent";
}

pub fn GetInd(self: ScriptComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *ScriptComponent) !void {
    const script = try self.mScriptHandle.GetAsset(ScriptAsset);
    try script.EditorRender();
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn jsonStringify(self: *const ScriptComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("FilePath");

    if (self.mScriptAssetHandle) |asset_handle| {
        const asset_file_data = try asset_handle.GetAsset(FileMetaData);
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
            const parsed_path = try std.json.innerParse([]const u8, allocator, reader, options);

            result.mScriptAssetHandle = AssetManager.GetAssetHandleRef(parsed_path, .Prj) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        }
    }

    return result;
}
