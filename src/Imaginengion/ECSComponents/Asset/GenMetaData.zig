const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const GenMetaData = @This();

pub const Name: []const u8 = "GenMetaData";

mLastModified: i128 = 0,

pub fn Deinit(_: *GenMetaData, _: *EngineContext) void {}
