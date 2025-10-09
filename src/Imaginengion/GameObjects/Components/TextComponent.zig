const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const ComponentsList = @import("../../GameObjects/Components.zig").ComponentsList;
const AssetManager = @import("../../Assets/AssetManager.zig");
const LinAlg = @import("../../Math/LinAlg.zig");
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;
const AssetsList = @import("../../Assets/Assets.zig");
const FileMetaData = AssetsList.FileMetaData;
const TextComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

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
mFontSize: u32 = 12,
mColor: Vec4f32 = Vec4f32{ 1.0, 1.0, 1.0, 1.0 },
mBounds: Vec2f32 = Vec2f32{ -100.0, 100.0 },

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
    //text box
    _ = imgui.igInputText("Text", self.mText.items.ptr, self.mText.items.len, imgui.ImGuiInputTextFlags_CallbackResize, InputTextCallback, @ptrCast(@constCast(&self)));

    //font name just as a text that can be drag dropped onto to change the text
    if (self.mTextAssetHandle) |text_asset| {
        const file_data_asset = try text_asset.GetAsset(FileMetaData);
        imgui.igTextUnformatted(file_data_asset.mRelPath.items.ptr, null);
        //drag drop target for ttf files from content browser
    }

    //font size, just set the integer
    _ = imgui.igInputInt("Font Size", @ptrCast(&self.mFontSize), 1, 5, imgui.ImGuiInputTextFlags_None);

    //bounds, have sliders for left ([0]) and right ([1])
    _ = imgui.igDragFloat2("Bounds L R", @ptrCast(&self.mBounds), 0.1, 0, 0, "%.3f", imgui.ImGuiSliderFlags_None);

    //color, do the color picker from imgui
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mColor), imgui.ImGuiColorEditFlags_None);
}

fn InputTextCallback(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.*.EventFlag == imgui.ImGuiInputTextFlags_CallbackResize) {
        const text_component: *TextComponent = @ptrCast(@alignCast(data.*.UserData.?));
        _ = text_component.mText.resize(text_component.mAllocator, @intCast(data.*.BufTextLen + 1)) catch return 0;
        data.*.Buf = text_component.mText.items.ptr;
    }
    return 0;
}

pub fn jsonStringify(self: *const TextComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("TextAssetHandle");
    if (self.mTextAssetHandle) |asset_handle| {
        const file_data_asset = try asset_handle.GetAsset(FileMetaData);
        try jw.write(file_data_asset.mRelPath.items);

        try jw.objectField("PathType");
        try jw.write(file_data_asset.mPathType);
    } else {
        try jw.write("No Text Handle");

        try jw.objectField("PathType");
        try jw.write("No Text Handle");
    }

    try jw.objectField("AtlasHandle");
    if (self.mAtlasHandle) |asset_handle| {
        const file_data_asset = try asset_handle.GetAsset(FileMetaData);
        try jw.write(file_data_asset.mRelPath.items);

        try jw.objectField("PathType");
        try jw.write(file_data_asset.mPathType);
    } else {
        try jw.write("No Atlas Handle");

        try jw.objectField("PathType");
        try jw.write("No Atlas Handle");
    }

    try jw.objectField("FontSize");
    try jw.write(self.mFontSize);

    try jw.objectField("Color");
    try jw.write(self.mColor);

    try jw.objectField("Bounds");
    try jw.write(self.mBounds);

    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!TextComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: TextComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "TextAssetHandle")) {
            const parsed_path = try std.json.innerParse([]const u8, allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, allocator, reader, options);

            result.mTextAssetHandle = AssetManager.GetAssetHandleRef(parsed_path, parsed_path_type) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        } else if (std.mem.eql(u8, field_name, "AtlasHandle")) {
            const parsed_path = try std.json.innerParse([]const u8, allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(FileMetaData.PathType, allocator, reader, options);

            result.mTextAssetHandle = AssetManager.GetAssetHandleRef(parsed_path, parsed_path_type) catch |err| {
                std.debug.print("error: {}\n", .{err});
                @panic("");
            };
        } else if (std.mem.eql(u8, field_name, "FontSize")) {
            result.mFontSize = try std.json.innerParse(u32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Color")) {
            result.mColor = try std.json.innerParse(Vec4f32, allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Bounds")) {
            result.mBounds = try std.json.innerParse(Vec2f32, allocator, reader, options);
        }
    }

    return result;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
