const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentsList = @import("../../GameObjects/Components.zig").ComponentsList;
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const AssetsList = @import("../../Assets/Assets.zig");
const FileMetaData = AssetsList.FileMetaData;
const Texture2D = @import("../../Assets/Assets.zig").Texture2D;
const EngineContext = @import("../../Core/EngineContext.zig");
const PathType = @import("../../Assets/AssetManager.zig").PathType;
const Material = @import("../../Physics/Material.zig");
const TextComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "TextComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TextComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mShouldRender: bool = true,
mText: std.ArrayList(u8) = .empty,
mTextAssetHandle: AssetHandle = .{},
mTexHandle: AssetHandle = .{},
mTexOptions: Texture2D.TexOptions = .{},
mMaterial: Material.SurfaceRenderMat = .{},
mFontSize: f32 = 9,
mBounds: Vec2(f32) = .{ .x = 8, .y = 8 },
mEngineAllocator: std.mem.Allocator = undefined,
mShouldEditTexture: bool = false,

pub fn Deinit(self: *TextComponent, engine_context: *EngineContext) !void {
    self.mTextAssetHandle.ReleaseAsset();
    self.mTexHandle.ReleaseAsset();
    self.mText.deinit(engine_context.EngineAllocator());
}

pub fn EditorRender(self: *TextComponent, engine_context: *EngineContext) !void {
    ImguiManager.RenderTextInput(engine_context, &self.mText, "Text");

    //font name just as a text that can be drag dropped onto to change the text
    ImguiManager.RenderAssetRef(engine_context, self.mTextAssetHandle, "Text Asset", "TextAsset");

    ImguiManager.RenderFloatInput(&self.mFontSize, "Font Size", 1, 5);

    //bounds, have sliders for left ([0]) and right ([1])
    ImguiManager.RenderFloat2Drag(&self.mBounds, "Bounds L R", 0.1, 0, 0);

    const texture_asset = try self.mTexHandle.GetAsset(engine_context, Texture2D);
    ImguiManager.RenderTexture2D(engine_context, &self.mTexHandle, texture_asset, &self.mShouldEditTexture);
    self.mTexOptions.ImguiRender(engine_context, &self.mShouldEditTexture, texture_asset);

    self.mMaterial.ImguiRender(engine_context);
}

pub fn jsonStringify(self: *const TextComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("TextAssetHandle");
    const text_asset_data = self.mTextAssetHandle.GetFileMetaData();
    try jw.write(text_asset_data.mRelPath.items);
    try jw.objectField("PathType");
    try jw.write(text_asset_data.mPathType);

    try jw.objectField("TextureAssetHandle");
    const file_data_texture = self.mTexHandle.GetFileMetaData();
    try jw.write(file_data_texture.mRelPath.items);
    try jw.objectField("PathType");
    try jw.write(file_data_texture.mPathType);

    try jw.objectField("Text");
    try jw.write(self.mText.items);

    try jw.objectField("FontSize");
    try jw.write(self.mFontSize);

    //texture options
    try jw.objectField("Color");
    try jw.write(self.mMaterial.mSurfaceColor);

    try jw.objectField("TilingFactor");
    try jw.write(self.mTexOptions.mTilingFactor);

    try jw.objectField("TextureUV0");
    try jw.write(self.mTexOptions.mTextureUV0);

    try jw.objectField("TextureUV1");
    try jw.write(self.mTexOptions.mTextureUV1);

    //bounds
    try jw.objectField("Bounds");
    try jw.write(self.mBounds);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!TextComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: TextComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "TextAssetHandle")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(PathType, frame_allocator, reader, options);

            result.mTextAssetHandle = engine_context.mAssetManager.GetAssetHandleRef(
                engine_context,
                .{ .File = .{ .rel_path = parsed_path, .path_type = parsed_path_type } },
            ) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        } else if (std.mem.eql(u8, field_name, "TextureAssetHandle")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(PathType, frame_allocator, reader, options);

            result.mTexHandle = engine_context.mAssetManager.GetAssetHandleRef(engine_context, .{ .File = .{ .rel_path = parsed_path, .path_type = parsed_path_type } }) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        } else if (std.mem.eql(u8, field_name, "FontSize")) {
            result.mFontSize = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Text")) {
            const text = try std.json.innerParse([]const u8, frame_allocator, reader, options);
            result.mText.appendSlice(engine_context.EngineAllocator(), text) catch {
                @panic("error appending slice, error out of memory");
            };
        } else if (std.mem.eql(u8, field_name, "Color")) {
            result.mMaterial.mSurfaceColor = try std.json.innerParse(Vec4(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TilingFactor")) {
            result.mTexOptions.mTilingFactor = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TextureUV0")) {
            result.mTexOptions.mTextureUV0 = try std.json.innerParse(Vec2(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TextureUV1")) {
            result.mTexOptions.mTextureUV1 = try std.json.innerParse(Vec2(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Bounds")) {
            result.mBounds = try std.json.innerParse(Vec2(f32), frame_allocator, reader, options);
        }
    }

    return result;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
