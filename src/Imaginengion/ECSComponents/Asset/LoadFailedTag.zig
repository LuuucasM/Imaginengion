const EngineContext = @import("../../Core/EngineContext.zig");

/// Marks an asset whose last load failed. AManager.GetAsset hands back the default asset for it
/// without trying again, since loading the same file a second time fails the same way (and some
/// loads, like a font's atlas generation, take seconds). A change to the file is what clears it,
/// through the FileUpdate event, so the next GetAsset tries the new contents.
const LoadFailedTag = @This();

pub const Name: []const u8 = "LoadFailedTag";

pub fn Deinit(_: *LoadFailedTag, _: *EngineContext) void {}
