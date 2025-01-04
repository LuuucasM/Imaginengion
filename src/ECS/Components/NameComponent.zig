const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../Entity.zig");
const NameComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const ImguiManager = @import("../../Imgui/Imgui.zig");
const ImguiEvent = @import("../../Imgui/ImguiEvent.zig").ImguiEvent;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

Name: [24]u8,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *NameComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn ImguiRender(self: *NameComponent, entity: Entity) !void {
    if (imgui.igSelectable_Bool(@typeName(NameComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
        const new_event = ImguiEvent{
            .ET_SelectComponentEvent = .{
                .mEditorWindow = EditorWindow.Init(self, entity),
            },
        };
        try ImguiManager.InsertEvent(new_event);
    }
}

pub fn GetName(self: NameComponent) []const u8 {
    _ = self;
    return "NameComponent";
}

pub fn GetInd(self: NameComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *NameComponent) !void {
    var buffer: [24]u8 = undefined;
    @memset(&buffer, 0);
    @memcpy(&buffer, &self.Name);

    if (imgui.igInputText("##Name", &buffer, buffer.len, imgui.ImGuiInputTextFlags_None, null, null) == true) {
        self.Name = buffer;
    }
}
