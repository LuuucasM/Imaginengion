const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const Entity = @import("../../GameObjects/Entity.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mScriptAssetHandle: AssetHandle = .{},

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = false;
pub const Name: []const u8 = "ScriptComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(self: *ScriptComponent, _: *EngineContext) !void {
    if (self.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
        self.mScriptAssetHandle.ReleaseAsset();
    }
}

pub fn jsonStringify(self: *const ScriptComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("FilePath");
    const asset_file_data = self.mScriptAssetHandle.GetFileMetaData();
    try jw.write(asset_file_data.mRelPath.items);

    try jw.objectField("PathType");
    try jw.write(asset_file_data.mPathType);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!ScriptComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: ScriptComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "FilePath")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, frame_allocator, reader, options);

            result.mScriptAssetHandle = engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), parsed_path, parsed_path_type) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        }
    }

    return result;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
