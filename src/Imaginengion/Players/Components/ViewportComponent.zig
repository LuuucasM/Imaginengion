const FrameBuffer = @import("../../FrameBuffer.zig");
const VertexArray = @import("../../VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffer.zig");
const AssetHandle = @import("../../AssetManager.zig").AssetHandle;
const ComponentsList = @import("../Components.zig").ComponentsList;
const ViewportComponent = @This();

mViewportWidth: usize,
mViewportHeight: usize,
mViewportFrameBuffer: FrameBuffer,
mViewportVertexArray: VertexArray,
mViewportVertexBuffer: VertexBuffer,
mViewportIndexBuffer: IndexBuffer,
mViewportShaderHandle: AssetHandle,

pub fn Deinit(self: *ViewportComponent) !void {
    self.mViewportFrameBuffer.Deinit();
    self.mViewportVertexArray.Deinit();
    self.mViewportVertexBuffer.Deinit();
    self.mViewportIndexBuffer.Deinit();
    self.mViewportShaderHandle.Deinit();
}

pub fn GetFrameBuffer(self: *ViewportComponent) FrameBuffer {
    return self.mViewportFrameBuffer;
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ViewportComponent) {
            break :blk i;
        }
    }
};
