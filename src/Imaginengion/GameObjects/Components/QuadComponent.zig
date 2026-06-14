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
const Material = @import("../../Materials/Material.zig");
const QuadComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

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
mMaterial: Material = .{},
mEditTexCoords: bool = false,

pub fn Deinit(self: *QuadComponent, _: *EngineContext) !void {
    self.mTexture.ReleaseAsset();
}

pub fn EditorRender(self: *QuadComponent, engine_context: *EngineContext) !void {
    _ = imgui.igCheckbox("Should Render?", &self.mShouldRender);

    imgui.igSeparator();

    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mMaterial.mSurfaceColor), imgui.ImGuiColorEditFlags_None);
    _ = imgui.igDragFloat("TilingFactor", &self.mTexOptions.mTilingFactor, 0.0, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);

    const texture_asset = try self.mTexture.GetAsset(engine_context, Texture2D);

    imgui.igImage(
        try engine_context.mImguiManager.GetImguiTexture(engine_context, texture_asset),
        .{ .x = 50.0, .y = 50.0 },
        // Always show full texture in preview
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
    );

    // Open tiling editor on double-click of the image
    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) and imgui.igIsMouseDoubleClicked_Nil(0)) {
        self.mEditTexCoords = true;
    }

    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            self.mTexture.ReleaseAsset();
            self.mTexture = try engine_context.mAssetManager.GetAssetHandleRef(engine_context, .{ .File = .{ .rel_path = path, .path_type = .Prj } });
        }
    }
    try self.EditTexCoords(engine_context, texture_asset);
}

fn EditTexCoords(self: *QuadComponent, engine_context: *EngineContext, texture_asset: *Texture2D) !void {
    if (!self.mEditTexCoords) return;
    //const window_flags = imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoSavedSettings | imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;
    imgui.igSetNextWindowSize(.{ .x = @floatFromInt(texture_asset.GetWidth()), .y = @floatFromInt(texture_asset.GetHeight()) }, imgui.ImGuiCond_Once);

    if (imgui.igBegin("Texture Coordinate Editor", &self.mEditTexCoords, 0)) {
        defer imgui.igEnd();
        // Compute image size to fit above the controls while preserving aspect ratio
        const available = imgui.igGetContentRegionAvail();
        const tex_w: f32 = @floatFromInt(texture_asset.GetWidth());
        const tex_h: f32 = @floatFromInt(texture_asset.GetHeight());
        const texture_aspect = if (tex_h > 0) tex_w / tex_h else 1.0;

        const frame_h = imgui.igGetFrameHeightWithSpacing();
        const text_h = imgui.igGetTextLineHeightWithSpacing();
        // Reserve space for: label + two sliders + a little padding
        const reserved_controls_h: f32 = text_h + frame_h * 2 + 8.0;
        const allowed_h = @max(available.y - reserved_controls_h, 50.0);

        var draw_w = available.x;
        var draw_h = draw_w / texture_aspect;
        if (draw_h > allowed_h) {
            draw_h = allowed_h;
            draw_w = draw_h * texture_aspect;
        }

        imgui.igImage(
            try engine_context.mImguiManager.GetImguiTexture(engine_context, texture_asset),
            .{ .x = draw_w, .y = draw_h },
            .{ .x = self.mTexOptions.mTextureUV0.x, .y = 1.0 - self.mTexOptions.mTextureUV0.y },
            .{ .x = self.mTexOptions.mTextureUV1.x, .y = 1.0 - self.mTexOptions.mTextureUV1.y },
        );

        // UV editors under the image
        imgui.igDummy(.{ .x = 0.0, .y = 8.0 });
        imgui.igSeparatorText("Texture Coordinates (UV)");

        // UV0 (Min)
        var uv0x: f32 = 0;
        if (imgui.igSliderFloat2("UV0 (Min) - Slider", &uv0x, 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_AlwaysClamp)) {
            self.mTexOptions.mTextureUV0.x = uv0x;
        }

        // UV1 (Max)
        var uv0y: f32 = 0;

        if (imgui.igSliderFloat2("UV1 (Max) - Slider", &uv0y, 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_AlwaysClamp)) {
            self.mTexOptions.mTextureUV0.y = uv0y;
        }

        // Clamp and enforce min <= max per component
        self.mTexOptions.mTextureUV0.x = std.math.clamp(self.mTexOptions.mTextureUV0.x, 0.0, 1.0);
        self.mTexOptions.mTextureUV0.y = std.math.clamp(self.mTexOptions.mTextureUV0.y, 0.0, 1.0);
        self.mTexOptions.mTextureUV1.x = std.math.clamp(self.mTexOptions.mTextureUV1.x, 0.0, 1.0);
        self.mTexOptions.mTextureUV1.y = std.math.clamp(self.mTexOptions.mTextureUV1.y, 0.0, 1.0);
        if (self.mTexOptions.mTextureUV0.x < self.mTexOptions.mTextureUV1.x) self.mTexOptions.mTextureUV0.x = self.mTexOptions.mTextureUV1.x;
        if (self.mTexOptions.mTextureUV0.y < self.mTexOptions.mTextureUV1.y) self.mTexOptions.mTextureUV1.y = self.mTexOptions.mTextureUV1.y;

        // Close editor on double-click or outside click
        if (imgui.igIsMouseDoubleClicked_Nil(0) and imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None)) {
            self.mEditTexCoords = false;
        }
    }
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
