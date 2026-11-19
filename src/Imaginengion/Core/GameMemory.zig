//! What of the application's memory is the game's own, part by part: its world, the objects loaded from files (the Asset
//! world), and the assets it uses, found by what its objects hold (every AssetHandle field of every component in those
//! worlds, plus the default texture, font and sound, which a game draws with when it names none). An asset the editor
//! uses too is the game's all the same; one only the editor uses (its icons, its own font) isn't.
//!
//! The rest of a game, the engine itself (the C libraries, the audio mixer, the renderer, the engine's structs, UI-only
//! data), can't be told apart from the editor's while the editor runs. So a game built with -Dstats measures it: the
//! whole game less these parts (Baseline), and writes it into the project (ProjectSettings/EngineBaseline.json), for the
//! editor to add to its own count of the parts (Total).
const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Assets = @import("../ECSComponents/AComponents.zig");
const TextureManager = @import("../TextureManager/TextureManager.zig");

const GameMemory = @This();

/// Where in the project the baseline a game measured is kept
pub const BASELINE_FILE = "ProjectSettings/EngineBaseline.json";

/// The game's own parts, in bytes
pub const Parts = struct {
    /// the game's world: its objects and everything they hold
    WorldCPU: u64 = 0,
    /// objects loaded from files, the Asset world
    ObjectsCPU: u64 = 0,
    /// the game's assets' own memory: decoded sounds, fonts' glyph tables, the rest's structs
    AssetsCPU: u64 = 0,
    /// the world's render targets and atlas slots
    WorldVideo: u64 = 0,
    /// the game's textures' and fonts' atlas slots
    AssetsVideo: u64 = 0,

    pub fn CPU(self: Parts) u64 {
        return self.WorldCPU + self.ObjectsCPU + self.AssetsCPU;
    }

    pub fn Video(self: Parts) u64 {
        return self.WorldVideo + self.AssetsVideo;
    }
};

/// The engine itself in a game: what a game built with -Dstats measured beyond its parts, at most, over a run
pub const Baseline = struct {
    CPUBytes: u64 = 0,
    VideoBytes: u64 = 0,
    /// when it was measured, YYYY-MM-DD
    Measured: []const u8 = "",
};

/// The game's parts with `game_world` as its world (the Simulate world while the editor plays). The assets are found
/// afresh each time, from what the objects hold now
pub fn MeasureParts(engine_context: *EngineContext, game_world: *WorldManager) !Parts {
    const scratch_allocator = engine_context.Scratch();
    const gpu = &engine_context.mGPUAllocator;
    const owner = engine_context.WorldTag(game_world);
    var parts: Parts = .{
        .WorldCPU = @intCast(game_world.mMemory.Totals().Bytes()),
        .ObjectsCPU = @intCast(engine_context.mAssetWorld.mMemory.Totals().Bytes()),
        .WorldVideo = gpu.CountsOf(owner).Bytes + gpu.AtlasBytesOf(owner),
    };

    var used: std.AutoArrayHashMapUnmanaged(AssetHandle.Type, void) = .empty;
    try CollectAssets(scratch_allocator, game_world, &used);
    try CollectAssets(scratch_allocator, &engine_context.mAssetWorld, &used);
    const internal = &engine_context.mAssetManager._internal;
    for ([_]?AssetHandle{ internal.DefaultTexture2DHandle, internal.DefaultTextHandle, internal.DefaultAudioHandle }) |held| {
        if (held) |handle| try used.put(scratch_allocator, handle.mID, {});
    }

    const asset_manager = &engine_context.mAssetManager;
    for (used.keys()) |asset_id| {
        if (asset_manager.GetLoadedAsset(Assets.Texture2D, asset_id)) |texture| {
            parts.AssetsVideo += TextureManager.SlotBytes(texture.GetTextureHandle());
            parts.AssetsCPU += @sizeOf(Assets.Texture2D);
        } else if (asset_manager.GetLoadedAsset(Assets.TextAsset, asset_id)) |font| {
            parts.AssetsVideo += TextureManager.SlotBytes(font.mAtlas.GetTextureHandle());
            parts.AssetsCPU += @sizeOf(Assets.TextAsset);
        } else if (asset_manager.GetLoadedAsset(Assets.AudioAsset, asset_id)) |sound| {
            parts.AssetsCPU += sound.GetSamples().len * @sizeOf(f32);
        }
    }
    return parts;
}

/// Every asset `world`'s objects hold a handle to, into `used`: every component with an AssetHandle field, in each of the
/// world's ECSs
fn CollectAssets(allocator: std.mem.Allocator, world: *WorldManager, used: *std.AutoArrayHashMapUnmanaged(AssetHandle.Type, void)) !void {
    //a world never started has no ECSs to walk (a test that doesn't use it): its memory node is only named once it is
    if (world.mMemory.mEngineContext == null) return;
    inline for (.{ &world.mEManager.mECSManager, &world.mSManager.mECSManager, &world.mPManager.mECSManager, &world.mGCManager.mECSManager }) |ecs| {
        inline for (@TypeOf(ecs.*).ComponentTypes) |component_type| {
            if (comptime !HoldsAssets(component_type)) continue;
            const ids = try ecs.GetGroup(allocator, .{ .Component = component_type });
            for (ids.items) |id| {
                const component = ecs.GetComponent(component_type, id) orelse continue;
                const info = @typeInfo(component_type).@"struct";
                inline for (info.field_types, info.field_names) |field_type, field_name| {
                    if (field_type != AssetHandle) continue;
                    const handle = @field(component, field_name);
                    if (handle.IsIDValid()) try used.put(allocator, handle.mID, {});
                }
            }
        }
    }
}

/// Whether a component type has an AssetHandle field
fn HoldsAssets(comptime component_type: type) bool {
    if (@typeInfo(component_type) != .@"struct") return false;
    for (@typeInfo(component_type).@"struct".field_types) |field_type| {
        if (field_type == AssetHandle) return true;
    }
    return false;
}

/// Today as YYYY-MM-DD, by the system clock
pub fn Today(io: std.Io, buffer: *[10]u8) []const u8 {
    const now = std.Io.Timestamp.now(io, .real).toSeconds();
    const day = (std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, now)) }).getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1 }) catch unreachable;
}
