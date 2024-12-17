const std = @import("std");
const AssetHandle = @import("AssetHandle.zig");
const Asset = @This();

mAssetHandle: AssetHandle,
mRefs: u32,
mAbsPath: []const u8,
mLastModified: i128,
mSize: u64,
mHash: u64,
mInternalID: u32,
