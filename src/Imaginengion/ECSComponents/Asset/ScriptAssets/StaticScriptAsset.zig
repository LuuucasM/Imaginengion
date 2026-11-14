//! A packaged game's scripts, for ScriptAsset: they're compiled into the game's exe, so there's nothing to build or load.
//! "game_scripts" is a table the game's build generates (build_script.zig), with the ScriptInfo of each script the game
//! loads. Only a packaged game has that module, and only a packaged game gets this far (ScriptAsset.Lib)
const std = @import("std");
const StaticScriptAsset = @This();

const game_scripts = @import("game_scripts");
const EngineContext = @import("../../../Core/EngineContext.zig");
const ScriptABI = @import("../../../Scripts/ScriptABI.zig");
const ProjectWalk = @import("../../../GameBuild/ProjectWalk.zig");

pub fn Build(_: *EngineContext, _: []const u8, _: []const u8) !void {}

/// The ScriptInfo of the script at rel_path, which is how the table knows it: abs_path is different on every machine
pub fn Open(_: *StaticScriptAsset, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, _: u32) !*const ScriptABI.ScriptInfo {
    const path = try ProjectWalk.Normalize(engine_context.Scratch(), rel_path);
    for (game_scripts.scripts) |script| {
        if (std.mem.eql(u8, script.mPath, path)) return script.mInfo;
    }
    std.log.err("{s} isn't compiled into the game: nothing the build could find uses it", .{rel_path});
    return error.AssetInitFailed;
}

pub fn Close(_: *StaticScriptAsset, _: *EngineContext) void {}

/// Whether any script compiled into the game has `hook` on objects of kind `owner`
pub fn HookIsUsed(comptime owner: ScriptABI.OwnerKind, comptime hook: ScriptABI.Hook) bool {
    for (game_scripts.scripts) |script| {
        if (script.mInfo.mOwner == owner and script.mInfo.HasHook(hook)) return true;
    }
    return false;
}
