const std = @import("std");

pub const AssetState = enum(u2) {
    NotLoaded,
    InCPU,
    InGPU,
};

pub const AssetHandle = struct {
    mID: u32,
    mLoadState: AssetState,
};

const Asset = @This();
mAssetHandle: AssetHandle,
mRefs: u32,
mPath: []const u8,
mLastModified: i128,
mSize: u64,
mHash: u64,
mMemoryLoc: ?*anyopaque,
