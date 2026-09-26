const EngineContext = @import("../../Core/EngineContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const VoiceAssetComponent = @This();

pub const Name: []const u8 = "VoiceAssetComponent";

/// The voice's own asset, used instead of its source's AudioComponent's. A detached voice gets this since its source
/// may be gone before it finishes. Holds its own reference, so the asset stays loaded until the voice is destroyed
mAsset: AssetHandle = .uninit,

pub fn Deinit(self: *VoiceAssetComponent, _: *EngineContext) void {
    self.mAsset.ReleaseAsset();
}
