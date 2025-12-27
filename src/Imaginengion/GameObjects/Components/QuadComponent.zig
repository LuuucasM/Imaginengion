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
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const QuadComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;

mShouldRender: bool = true,
mTexture: AssetHandle = undefined,
mTexOptions: Texture2D.TexOptions = .{},
mEditTexCoords: bool = false,

pub fn Deinit(_: *QuadComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == QuadComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
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

pub fn EditorRender(self: *QuadComponent, _: std.mem.Allocator) !void {
    _ = imgui.igCheckbox("Should Render?", &self.mShouldRender);

    imgui.igSeparator();

    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mTexOptions.mColor), imgui.ImGuiColorEditFlags_None);
    _ = imgui.igDragFloat("TilingFactor", &self.mTexOptions.mTilingFactor, 0.0, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);

    const texture_asset = try self.mTexture.GetAsset(Texture2D);
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, (texture_asset.GetID()))));
    imgui.igImage(
        texture_id,
        .{ .x = 50.0, .y = 50.0 },
        // Always show full texture in preview
        .{ .x = 0.0, .y = 1.0 },
        .{ .x = 1.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    );

    // Open tiling editor on double-click of the image
    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) and imgui.igIsMouseDoubleClicked_Nil(0)) {
        self.mEditTexCoords = true;
    }

    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            AssetM.ReleaseAssetHandleRef(&self.mTexture);
            self.mTexture = try AssetM.GetAssetHandleRef(path, .Prj);
        }
    }
    try self.EditTexCoords(texture_asset);
}

fn EditTexCoords(self: *QuadComponent, texture_asset: *Texture2D) !void {
    if (!self.mEditTexCoords) return;
    //const window_flags = imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoSavedSettings | imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;
    imgui.igSetNextWindowSize(.{ .x = @floatFromInt(texture_asset.GetWidth()), .y = @floatFromInt(texture_asset.GetHeight()) }, imgui.ImGuiCond_Once);

    if (imgui.igBegin("Texture Coordinate Editor", &self.mEditTexCoords, 0)) {
        defer imgui.igEnd();
        // Compute image size to fit above the controls while preserving aspect ratio
        var available: imgui.struct_ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&available);
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

        const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, texture_asset.GetID())));

        imgui.igImage(
            texture_id,
            .{ .x = draw_w, .y = draw_h },
            .{ .x = self.mTexOptions.mTexCoords[0], .y = 1.0 - self.mTexOptions.mTexCoords[1] },
            .{ .x = self.mTexOptions.mTexCoords[2], .y = 1.0 - self.mTexOptions.mTexCoords[3] },
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
            .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        );

        // UV editors under the image
        imgui.igDummy(.{ .x = 0.0, .y = 8.0 });
        imgui.igSeparatorText("Texture Coordinates (UV)");

        // UV0 (Min)
        _ = imgui.igSliderFloat2(
            "UV0 (Min) - Slider",
            @ptrCast(&self.mTexOptions.mTexCoords[0]),
            0.0,
            1.0,
            "%.3f",
            imgui.ImGuiSliderFlags_AlwaysClamp,
        );

        // UV1 (Max)
        _ = imgui.igSliderFloat2(
            "UV1 (Max) - Slider",
            @ptrCast(&self.mTexOptions.mTexCoords[1]),
            0.0,
            1.0,
            "%.3f",
            imgui.ImGuiSliderFlags_AlwaysClamp,
        );

        // Clamp and enforce min <= max per component
        self.mTexOptions.mTexCoords[0] = std.math.clamp(self.mTexOptions.mTexCoords[0], 0.0, 1.0);
        self.mTexOptions.mTexCoords[1] = std.math.clamp(self.mTexOptions.mTexCoords[1], 0.0, 1.0);
        self.mTexOptions.mTexCoords[2] = std.math.clamp(self.mTexOptions.mTexCoords[2], 0.0, 1.0);
        self.mTexOptions.mTexCoords[3] = std.math.clamp(self.mTexOptions.mTexCoords[3], 0.0, 1.0);
        if (self.mTexOptions.mTexCoords[0] < self.mTexOptions.mTexCoords[2]) self.mTexOptions.mTexCoords[0] = self.mTexOptions.mTexCoords[2];
        if (self.mTexOptions.mTexCoords[1] < self.mTexOptions.mTexCoords[3]) self.mTexOptions.mTexCoords[1] = self.mTexOptions.mTexCoords[3];

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
    try jw.write(self.mTexOptions.mColor);

    try jw.objectField("TilingFactor");
    try jw.write(self.mTexOptions.mTilingFactor);

    try jw.objectField("TexCoords");
    try jw.write(self.mTexOptions.mTexCoords);

    try jw.objectField("Texture");
    const asset_file_data = try self.mTexture.GetAsset(FileMetaData);
    try jw.write(asset_file_data.mRelPath.items);

    try jw.objectField("PathType");
    try jw.write(asset_file_data.mPathType);

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
            result.mTexOptions.mColor = try std.json.innerParse(Vec4f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TilingFactor")) {
            result.mTexOptions.mTilingFactor = try std.json.innerParse(f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TexCoords")) {
            result.mTexOptions.mTexCoords = try std.json.innerParse(Vec4f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Texture")) {
            const parsed_path = try std.json.innerParse([]const u8, allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, allocator, reader, options);

            result.mTexture = AssetManager.GetAssetHandleRef(parsed_path, parsed_path_type) catch |err| {
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
