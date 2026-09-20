const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AssetMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

mRefs: usize = 0,

pub fn Deinit(_: *AssetMetaData, _: *EngineContext) void {}

pub const Name: []const u8 = "AssetMetaData";
