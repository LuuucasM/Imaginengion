const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const ComponentsList = @import("../../GameObjects/Components.zig").ComponentsList;
const AssetManager = @import("../../Assets/AssetManager.zig");
const LinAlg = @import("../../Math/LinAlg.zig");
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;
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
    _ = imgui.igInputText("Text", self.mText.items.ptr, self.mText.items.len, imgui.ImGuiInputTextFlags_CallbackResize, InputTextCallback, &self.mText);

    //font name just as a text that can be drag dropped onto to change the text

    //font size, just set the integer

    //bounds, have sliders for left ([0]) and right ([1])

    //color, do the color picker from imgui

}

fn InputTextCallback(data: *imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.EventFlag == imgui.ImGuiInputTextFlags_CallbackResize) {
        const list: *std.ArrayList(u8) = @ptrCast(@alignCast(data.UserData.?));
        _ = list.resize(data.BufTextLen + 1) catch return 0;
        data.Buf = list.items.ptr;
    }
    return 0;
}

pub fn jsonStringify(self: *const TextComponent, jw: anytype) !void {
    //TODO
}

pub fn jsonParse(allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!TextComponent {
    //TODO
}
