const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const Vec2f32 = @import("../../Math/LinAlg.zig").Vec2f32;
const AssetM = @import("../../Assets/AssetManager.zig");
const Assets = @import("../../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const FileMetaData = Assets.FileMetaData;
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;
const AssetManager = @import("../../Assets/AssetManager.zig");
const QuadComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

mShouldRender: bool = true,
mColor: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
mTilingFactor: f32 = 1.0,
mTexCoords: [2]Vec2f32 = [2]Vec2f32{
    Vec2f32{ 0, 0 },
    Vec2f32{ 1, 1 },
},
mTexture: AssetHandle = .{ .mID = AssetHandle.NullHandle },

pub fn Deinit(_: *QuadComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == QuadComponent) {
            break :blk i;
        }
    }
};

pub fn GetName(self: QuadComponent) []const u8 {
    _ = self;
    return "QuadComponent";
}

pub fn GetInd(self: QuadComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *QuadComponent) !void {
    _ = imgui.igCheckbox("Should Render?", &self.mShouldRender);
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mColor), imgui.ImGuiColorEditFlags_None);
    _ = imgui.igDragFloat("TilingFactor", &self.mTilingFactor, 0.0, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, (try self.mTexture.GetAsset(Texture2D)).GetID())));
    imgui.igImage(
        texture_id,
        .{ .x = 50.0, .y = 50.0 },
        .{ .x = self.mTexCoords[0][0], .y = 1.0 - self.mTexCoords[0][1] },
        .{ .x = self.mTexCoords[1][0], .y = 1.0 - self.mTexCoords[1][1] },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    );

    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            if (self.mTexture.mID != AssetHandle.NullHandle) {
                AssetM.ReleaseAssetHandleRef(&self.mTexture);
            }
            self.mTexture = try AssetM.GetAssetHandleRef(path, .Prj);
        }
    }
}

pub fn jsonStringify(self: *const QuadComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("ShouldRender");
    try jw.write(self.mShouldRender);

    try jw.objectField("Color");
    try jw.write(self.mColor);

    try jw.objectField("TilingFactor");
    try jw.write(self.mTilingFactor);

    try jw.objectField("TexCoords");
    try jw.write(self.mTexCoords);

    try jw.objectField("Texture");
    if (self.mTexture.mID != AssetHandle.NullHandle) {
        const asset_file_data = try self.mTexture.GetAsset(FileMetaData);
        try jw.write(asset_file_data.mRelPath.items);
    } else {
        try jw.write("No Script Asset");
    }

    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!QuadComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: QuadComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "ShouldRender")) {
            result.mShouldRender = try std.json.innerParse(bool, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Color")) {
            result.mColor = try std.json.innerParse(Vec4f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TilingFactor")) {
            result.mTilingFactor = try std.json.innerParse(f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TexCoords")) {
            result.mTexCoords = try std.json.innerParse([2]Vec2f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Texture")) {
            const parsed_path = try std.json.innerParse([]const u8, allocator, reader, options);
            result.mTexture = AssetManager.GetAssetHandleRef(parsed_path, .Prj) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        }
    }

    return result;
}
