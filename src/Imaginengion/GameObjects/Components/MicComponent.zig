const std = @import("std");
const BUFFER_CAPACITY = @import("../../AudioManager/AudioManager.zig").BUFFER_CAPACITY;
const TAudioBuffer = @import("../../AudioManager/AudioManager.zig").TAudioBuffer;
const ComponentsList = @import("../Components.zig").ComponentsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const MicComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = false;
pub const Name: []const u8 = "MicComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == MicComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mAudioBuffer: TAudioBuffer = TAudioBuffer.Init(),

pub fn Deinit(_: *MicComponent, _: *EngineContext) !void {}

pub fn jsonStringify(_: *const MicComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("TempVal");
    try jw.write(123);

    try jw.endObject();
}

pub fn jsonParse(_: std.mem.Allocator, reader: anytype, _: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!MicComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    while (true) {
        const token = try reader.next();
        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };
        _ = field_name;
    }

    return MicComponent{};
}
