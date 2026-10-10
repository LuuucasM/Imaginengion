const std = @import("std");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const ComputeOutput = @import("../../Renderer/Renderer.zig").ComputeOutput;
const Texture2D = @import("../AComponents.zig").Texture2D;

const RenderTargetComponent = @This();

pub const Editable = false;
pub const Name: []const u8 = "RenderTargetComponent";

/// The GPU texture is made by the renderer, never by making the component (loading, cloning, a new player): the
/// first fit of the target to the size it is drawn at (SetViewportSize, Viewports.FitPlayerToQuad) creates it, and
/// what draws or shows the target checks IsCreated first. So a script, which carries its own copy of the engine code
/// it calls and none of SDL, can load scenes and make players
mComputeTexture: ComputeOutput = .empty,
/// Where a quad showing this target (ViewportComponent) samples it from: a slot in the texture manager, the target's
/// size, which Shown copies the target into. Null until something shows it, and again after the target changes size
mShownSlot: ?u32 = null,
mShownWidth: usize = 0,
mShownHeight: usize = 0,

pub fn Deinit(self: *RenderTargetComponent, engine_context: *EngineContext) void {
    self.ReleaseShownSlot(engine_context);
    self.mComputeTexture.Deinit(engine_context);
}

/// What a quad samples to show this target, and what has to be copied there before it does
pub const Shown = struct {
    Handle: u32,
    Width: usize,
    Height: usize,
    /// the target's GPU texture, copied into the slot (TextureManager.CopyFromTexture) by the draw that shows it
    Source: *anyopaque,
};

/// The texture manager slot a quad samples to show the target, the target's size: made the first time and again
/// whenever the target's size changes. The draw that shows it copies the target in first (Renderer.EndRendering), so it
/// shows what the target was last drawn with. Null while the target has no texture, or is too big for a slot
pub fn ShownSlot(self: *RenderTargetComponent, engine_context: *EngineContext) !?Shown {
    if (!self.mComputeTexture.IsCreated()) return null;
    const width = self.mComputeTexture.GetWidth();
    const height = self.mComputeTexture.GetHeight();
    const texture_manager = &engine_context.mRenderer.mTextureManager;
    if (self.mShownSlot == null or self.mShownWidth != width or self.mShownHeight != height) {
        self.ReleaseShownSlot(engine_context);
        self.mShownSlot = texture_manager.Register(engine_context, null, width, height) catch |err| switch (err) {
            error.TextureTooLarge => return null,
            else => return err,
        };
        self.mShownWidth = width;
        self.mShownHeight = height;
    }
    return .{ .Handle = self.mShownSlot.?, .Width = width, .Height = height, .Source = self.mComputeTexture.GetTexture() };
}

fn ReleaseShownSlot(self: *RenderTargetComponent, engine_context: *EngineContext) void {
    if (self.mShownSlot) |slot| engine_context.mRenderer.mTextureManager.Unregister(slot);
    self.mShownSlot = null;
}

/// The GPU texture is owned, so a copy can't share it: a plain value copy would share the handle, and whichever copy
/// is deinit first frees it out from under the other. The copy starts with none, see the GPU texture note below
pub fn Clone(_: *const RenderTargetComponent, _: *EngineContext) !RenderTargetComponent {
    return .{};
}

pub fn GetOutputTexture(self: *RenderTargetComponent) *Texture2D {
    return self.mComputeTexture.GetColorTexture(0);
}

pub fn SetViewportSize(self: *RenderTargetComponent, engine_context: *EngineContext, width: usize, height: usize) !void {
    try self.mComputeTexture.Resize(engine_context, width, height);
}

//nothing to save, the render target is recreated on load
pub fn jsonStringify(_: *const RenderTargetComponent, jw: anytype) !void {
    try jw.beginObject();
    try jw.endObject();
}

pub fn jsonParse(_: std.mem.Allocator, reader: anytype, _: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!RenderTargetComponent {
    try reader.skipValue();
    return .{};
}
