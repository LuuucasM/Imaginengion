const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const NameComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Name: []const u8 = "NameComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mName: std.ArrayList(u8) = .{},
mAllocator: std.mem.Allocator = undefined,

pub fn Deinit(self: *NameComponent, _: *EngineContext) !void {
    self.mName.deinit(self.mAllocator);
}

pub fn EditorRender(self: *NameComponent, engine_context: *EngineContext) !void {
    const text = try engine_context.FrameAllocator().dupeZ(u8, self.mName.items);
    if (imgui.igInputText("Text", text.ptr, text.len + 1, imgui.ImGuiInputTextFlags_CallbackResize, InputTextCallback, @ptrCast(self))) {
        _ = self.mName.swapRemove(self.mName.items.len - 1);
    }
}
fn InputTextCallback(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.*.EventFlag == imgui.ImGuiInputTextFlags_CallbackResize) {
        const name_component: *NameComponent = @ptrCast(@alignCast(data.*.UserData.?));
        _ = name_component.mName.resize(name_component.mAllocator, @intCast(data.*.BufTextLen + 1)) catch return 0;
        data.*.Buf = name_component.mName.items.ptr;
    }
    return 0;
}

pub fn jsonStringify(self: *const NameComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("Name");
    try jw.write(self.mName.items);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!NameComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: NameComponent = .{};

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "Name")) {
            const name = try std.json.innerParse([]const u8, frame_allocator, reader, options);
            result.mAllocator = engine_context.EngineAllocator();
            result.mName.appendSlice(engine_context.EngineAllocator(), name) catch {
                @panic("error appending slice, error out of memory");
            };
        }
    }

    return result;
}
