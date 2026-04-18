const std = @import("std");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const OutputFrameBuffer = @import("../../Renderer/Renderer.zig").OutputFrameBuffer;

const RenderTargetComponent = @This();

pub const Editable = false;
pub const Name: []const u8 = "RenderTargetComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RenderTargetComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mFrameBuffer: OutputFrameBuffer = .empty,

pub fn Deinit(self: *RenderTargetComponent, engine_context: *EngineContext) !void {
    self.mFrameBuffer.Deinit(engine_context.EngineAllocator());
}

pub fn jsonStringify(_: *const RenderTargetComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("IsExist");
    try jw.write(0);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, _: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!RenderTargetComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "IsExist")) {
            continue;
        }
    }

    return RenderTargetComponent{ .mFrameBuffer = .empty.Init(engine_context, 1600, 900) };
}
