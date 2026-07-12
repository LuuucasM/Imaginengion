const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const Assets = @import("../../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const FileMetaData = Assets.FileMetaData;
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../Entity.zig");
const Player = @import("../../Players/Player.zig");
const RenderTargetComponent = @import("../Components.zig").RenderTargetComponent;
const PathType = @import("../../Assets/AssetManager.zig").PathType;
const Material = @import("../../Physics/Material.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const QuadComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "QuadComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == QuadComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mShouldRender: bool = true,
mTexture: AssetHandle = .empty,
mTexOptions: Texture2D.TexOptions = .{},
mMaterial: Material.SurfaceRenderMat = .default,
mEditTexCoords: bool = false,

pub fn Deinit(self: *QuadComponent, _: *EngineContext) !void {
    self.mTexture.ReleaseAsset();
}

pub fn EditorRender(self: *QuadComponent, engine_context: *EngineContext) !void {
    ImguiManager.RenderBool(&self.mShouldRender, "Should Render?");

    self.mMaterial.ImguiRender();

    const texture_asset = try self.mTexture.GetAsset(engine_context, Texture2D);

    self.mTexOptions.ImguiRender(engine_context, &self.mEditTexCoords, texture_asset);

    ImguiManager.RenderTexture2D(engine_context, &self.mTexture, texture_asset, &self.mEditTexCoords);
}

pub fn jsonStringify(self: *const QuadComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("ShouldRender");
    try jw.write(self.mShouldRender);

    try jw.objectField("Color");
    try jw.write(self.mMaterial.mSurfaceColor);

    try jw.objectField("TilingFactor");
    try jw.write(self.mTexOptions.mTilingFactor);

    try self.mTexture.jsonStringify(jw);

    try jw.objectField("TextureUV0");
    try jw.write(self.mTexOptions.mTextureUV0);

    try jw.objectField("TextureUV1");
    try jw.write(self.mTexOptions.mTextureUV1);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!QuadComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: QuadComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "ShouldRender")) {
            result.mShouldRender = try std.json.innerParse(bool, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Color")) {
            result.mMaterial.mSurfaceColor = try std.json.innerParse(Vec4(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TilingFactor")) {
            result.mTexOptions.mTilingFactor = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TextureUV0")) {
            result.mTexOptions.mTextureUV0 = try std.json.innerParse(Vec2(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TextureUV1")) {
            result.mTexOptions.mTextureUV1 = try std.json.innerParse(Vec2(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Texture")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(PathType, frame_allocator, reader, options);

            result.mTexture = engine_context.mAssetManager.GetAssetHandleRef(
                engine_context,
                .{ .File = .{ .rel_path = parsed_path, .path_type = parsed_path_type } },
            ) catch |err| {
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
