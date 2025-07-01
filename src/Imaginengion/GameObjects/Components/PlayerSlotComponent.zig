const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Player/Player.zig");
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetManager = @import("../../Assets/AssetManager.zig");

const PlayerSlotComponent = @This();

mPlayerEntity: Player.Type = Player.NullPlayer,

//viewport stuff
mViewportWidth: usize,
mViewportHeight: usize,
mViewportFrameBuffer: FrameBuffer,
mViewportVertexArray: VertexArray,
mViewportVertexBuffer: VertexBuffer,
mViewportIndexBuffer: IndexBuffer,
mViewportShaderHandle: AssetHandle,

pub fn Deinit(self: *PlayerSlotComponent) !void {
    self.mViewportFrameBuffer.Deinit();
    self.mViewportVertexArray.Deinit();
    self.mViewportVertexBuffer.Deinit();
    self.mViewportIndexBuffer.Deinit();
    AssetManager.ReleaseAsset(self.mViewportShaderHandle);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i;
        }
    }
};
