const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AssetMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

mRefs: usize = 0,

/// One more reference. Atomic, like DropRef: hooks running side by side in a batch (Transactions.RunBatch) take and give
/// back references to the same asset when they copy components that hold its handle
pub fn AddRef(self: *@This()) void {
    _ = @atomicRmw(usize, &self.mRefs, .Add, 1, .monotonic);
}

/// One reference fewer, see AddRef
pub fn DropRef(self: *@This()) void {
    _ = @atomicRmw(usize, &self.mRefs, .Sub, 1, .monotonic);
}

pub fn Deinit(_: *AssetMetaData, _: *EngineContext) void {}

pub const Name: []const u8 = "AssetMetaData";
