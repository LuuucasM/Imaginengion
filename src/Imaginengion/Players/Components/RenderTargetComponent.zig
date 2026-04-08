const std = @import("std");
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const TextureFormat = @import("../../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const RenderTargetComponent = @This();

pub const Name: []const u8 = "RenderTargetComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RenderTargetComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mFrameBuffer: FrameBuffer = undefined,
mVertexArray: VertexArray = undefined,
mVertexBuffer: VertexBuffer = undefined,
mIndexBuffer: IndexBuffer = undefined,

pub fn Deinit(self: *RenderTargetComponent, engine_context: *EngineContext) !void {
    self.mFrameBuffer.Deinit(engine_context.EngineAllocator());
    self.mVertexArray.Deinit(engine_context.EngineAllocator());
    self.mVertexBuffer.Deinit(engine_context.EngineAllocator());
    self.mIndexBuffer.Deinit();
}

pub fn SetViewportSize(self: *RenderTargetComponent, width: usize, height: usize) void {
    self.mFrameBuffer.Resize(width, height);
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

    return RenderTargetComponent{
        .mFrameBuffer = FrameBuffer.Init(engine_context.EngineAllocator(), &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900),
        .mVertexArray = VertexArray.Init(),
        .mVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32)),
        .mIndexBuffer = IndexBuffer.Init([6]u32{ 0, 1, 2, 2, 3, 0 }),
    };
}
