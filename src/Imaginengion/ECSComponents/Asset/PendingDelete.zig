const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");

const PendingDelete = @This();

pub const Name: []const u8 = "PendingDelete";

//why the asset is on its way out, as AManager.AssetErrorFlags bits. The flags live in AManager
//because it is what sets and reads them; this only carries the value
mReason: u32 = 0,

//when it was first marked, so the sweep can give the file a grace period to come back
mTime: std.Io.Timestamp = .zero,

pub fn Deinit(_: *PendingDelete, _: *EngineContext) void {}
