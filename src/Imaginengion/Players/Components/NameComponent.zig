const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "NameComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
pub const empty: NameComponent = .{
    .mName = .empty,
};

mName: std.ArrayList(u8) = .empty,

pub fn Deinit(self: *NameComponent, engine_context: *EngineContext) !void {
    self.mName.deinit(engine_context.EngineAllocator());
}

pub fn EditorRender(self: *NameComponent, engine_context: *EngineContext) !void {
    ImguiManager.RenderTextInput(engine_context, &self.mName, "Name");
}

pub fn jsonStringify(self: *const NameComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("Name");
    try jw.write(self.mName.items);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!NameComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: NameComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "Name")) {
            const name = try std.json.innerParse([]const u8, frame_allocator, reader, options);
            result.mName.appendSlice(engine_context.EngineAllocator(), name) catch {
                @panic("error appending slice, error out of memory");
            };
        }
    }

    return result;
}
