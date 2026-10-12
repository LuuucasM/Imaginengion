const EngineContext = @import("../../Core/EngineContext.zig");

/// Marks an asset whose file changed last frame. Added with the FileUpdate event that unloads the asset, and taken off
/// again at the start of the next AManager.OnUpdate, so for one frame anything built from the old contents can see it
/// has to catch up. ScriptsProcessor.SyncScripts uses it to swap a script for its new build and retag its hooks.
const FileChangedTag = @This();

pub const Name: []const u8 = "FileChangedTag";

pub fn Deinit(_: *FileChangedTag, _: *EngineContext) void {}
