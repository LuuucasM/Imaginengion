const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Players/Player.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const PlayerSlotComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "PlayerSlotComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mPlayerEntity: Player = .{},

pub fn Deinit(_: *PlayerSlotComponent, _: *EngineContext) !void {}

pub fn EditorRender(_: *PlayerSlotComponent, _: *EngineContext) !void {}

pub fn jsonStringify(_: *const PlayerSlotComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("Blah");
    try jw.write(0);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!PlayerSlotComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "Name")) {
            const num = try std.json.innerParse(u8, frame_allocator, reader, options);
            _ = num;
        }
    }

    return PlayerSlotComponent{};
}
