const imgui = @import("../../Core/CImports.zig").imgui;
const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();

Name: [24]u8,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

pub fn ImguiRender(self: *NameComponent) void {
    var buffer: [24]u8 = undefined;
    @memset(buffer, 0);
    @memcpy(buffer, self.Name);

    if (imgui.igInputText("##Name", buffer, buffer.len) == true){
        self.Name = buffer;
    }
}