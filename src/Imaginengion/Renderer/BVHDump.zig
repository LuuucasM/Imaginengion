//! The editor's BVH dump (F7): one overlay pass's camera, shapes and BVH, as the GPU got them, written to a file. A
//! debugging aid: a test can read it back and fire that pass's rays offline, to see which boxes a pixel's walk went
//! into and why it couldn't pass over them. The masks and programs aren't in it, so a replay can't cut masked shapes
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const BVH = @import("../Core/BVH.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ShapeData = @import("Renderer2D.zig").ShapeData;
const PushConstants = @import("RenderPipeline.zig").SDFPushConstants;

/// Written into the folder the editor runs in
pub const FILE_NAME = "bvh_dump.json";

pub const Dump = struct {
    /// the pass's push constants: its camera, its far distance and its viewport size among them
    Camera: PushConstants,
    /// the shapes as uploaded: the direct ones first (Camera.mDirectCount of them), in their BVH's order
    Shapes: []const ShapeData,
    Nodes: []const BVH.Node,
};

/// Writes `dump` to FILE_NAME, replacing the last one
pub fn Write(engine_context: *EngineContext, dump: Dump) !void {
    const zone = Tracy.ZoneInit("BVHDump::Write", @src());
    defer zone.Deinit();

    var out: std.Io.Writer.Allocating = .init(engine_context.FrameAllocator());
    defer out.deinit();
    try std.json.Stringify.value(dump, .{}, &out.writer);
    try std.Io.Dir.cwd().writeFile(engine_context.Io(), .{ .sub_path = FILE_NAME, .data = out.written() });
}

/// Reads a dump back, everything in it allocated in `allocator` (an arena does)
pub fn Read(allocator: std.mem.Allocator, contents: []const u8) !Dump {
    return std.json.parseFromSliceLeaky(Dump, allocator, contents, .{});
}
