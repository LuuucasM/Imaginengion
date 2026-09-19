const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComputeOutput = @import("../../Renderer/Renderer.zig").ComputeOutput;
const Texture2D = @import("../../Assets/Assets.zig").Texture2D;
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const RenderTargetComponent = @This();

pub const Editable = false;
pub const Name: []const u8 = "RenderTargetComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RenderTargetComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mComputeTexture: ComputeOutput = .empty,

pub fn Deinit(self: *RenderTargetComponent, engine_context: *EngineContext) !void {
    self.mComputeTexture.Deinit(engine_context);
}

pub fn GetOutputTexture(self: *RenderTargetComponent) *Texture2D {
    return self.mComputeTexture.GetColorTexture(0);
}

//nothing to save, the render target is recreated on load
pub fn jsonStringify(_: *const RenderTargetComponent, jw: anytype) !void {
    try jw.beginObject();
    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, _: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!RenderTargetComponent {
    try reader.skipValue();

    const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);

    var compute_texture: ComputeOutput = .empty;
    compute_texture.Init(engine_context, 1600, 900) catch |err| {
        std.debug.panic("Failed to create render target while deserializing: {}", .{err});
    };

    return RenderTargetComponent{ .mComputeTexture = compute_texture };
}
