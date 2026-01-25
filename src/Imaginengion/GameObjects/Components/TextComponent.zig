const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentsList = @import("../../GameObjects/Components.zig").ComponentsList;
const LinAlg = @import("../../Math/LinAlg.zig");
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;
const AssetsList = @import("../../Assets/Assets.zig");
const FileMetaData = AssetsList.FileMetaData;
const Texture2D = @import("../../Assets/Assets.zig").Texture2D;
const EngineContext = @import("../../Core/EngineContext.zig");
const TextComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Editable: bool = true;
pub const Name: []const u8 = "TextComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TextComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mShouldRender: bool = true,
mText: std.ArrayList(u8) = .{},
mTextAssetHandle: AssetHandle = .{},
mTexHandle: AssetHandle = .{},
mTexOptions: Texture2D.TexOptions = .{},
mFontSize: f32 = 9,
mBounds: Vec2f32 = Vec2f32{ 8, 8 },
mEngineAllocator: std.mem.Allocator = undefined,

pub fn Deinit(self: *TextComponent, engine_context: *EngineContext) !void {
    self.mTextAssetHandle.ReleaseAsset();
    self.mTexHandle.ReleaseAsset();
    self.mText.deinit(engine_context.EngineAllocator());
}

pub fn EditorRender(self: *TextComponent, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();
    //text box
    const text = try frame_allocator.dupeZ(u8, self.mText.items);
    self.mEngineAllocator = engine_context.EngineAllocator();
    if (imgui.igInputText("Text", text.ptr, text.len + 1, imgui.ImGuiInputTextFlags_CallbackResize, InputTextCallback, @ptrCast(self))) {
        _ = self.mText.swapRemove(self.mText.items.len - 1);
    }

    //font name just as a text that can be drag dropped onto to change the text
    const file_data_asset = self.mTextAssetHandle.GetFileMetaData();
    const name = std.fs.path.stem(std.fs.path.basename(file_data_asset.mRelPath.items));
    const name_term = try frame_allocator.dupeZ(u8, name);
    imgui.igTextUnformatted(name_term, null);
    //drag drop target for ttf files from content browser

    _ = imgui.igInputFloat("Font Size", @ptrCast(&self.mFontSize), 1, 5, "%.3f", imgui.ImGuiInputTextFlags_None);

    //bounds, have sliders for left ([0]) and right ([1])
    _ = imgui.igDragFloat2("Bounds L R", @ptrCast(&self.mBounds), 0.1, 0, 0, "%.3f", imgui.ImGuiSliderFlags_None);

    //color, do the color picker from imgui
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mTexOptions.mColor), imgui.ImGuiColorEditFlags_None);
}

fn InputTextCallback(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.*.EventFlag == imgui.ImGuiInputTextFlags_CallbackResize) {
        const text_component: *TextComponent = @ptrCast(@alignCast(data.*.UserData.?));
        _ = text_component.mText.resize(text_component.mEngineAllocator, @intCast(data.*.BufTextLen + 1)) catch return 0;
        data.*.Buf = text_component.mText.items.ptr;
    }
    return 0;
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
    try jw.write(self.mTexOptions.mColor);

    try jw.objectField("TilingFactor");
    try jw.write(self.mTexOptions.mTilingFactor);

    try jw.objectField("TexCoords");
    try jw.write(self.mTexOptions.mTexCoords);

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

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, frame_allocator, reader, options);

            result.mTextAssetHandle = engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), parsed_path, parsed_path_type) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        } else if (std.mem.eql(u8, field_name, "TextureAssetHandle")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, frame_allocator, reader, options);

            result.mTexHandle = engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), parsed_path, parsed_path_type) catch |err| {
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
            result.mTexOptions.mColor = try std.json.innerParse(Vec4f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TilingFactor")) {
            result.mTexOptions.mTilingFactor = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "TexCoords")) {
            result.mTexOptions.mTexCoords = try std.json.innerParse(Vec4f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Bounds")) {
            result.mBounds = try std.json.innerParse(Vec2f32, frame_allocator, reader, options);
        }
    }

    return result;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
