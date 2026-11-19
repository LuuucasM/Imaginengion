//! The platforms a project's game is made for, each with a budget of CPU memory and of video memory, and the one the
//! editor checks against now (the target). Kept per project, in ProjectSettings/Platforms.json (see Project.zig); a new
//! project has one, PC, with budgets roomy enough that nothing is near them until they are set.
//!
//! Check compares what the game is using with the target's budgets: in the editor, as near as the editor can tell what
//! is the game's (EditorUsage), in a game what it all is (GameUsage). Going over is a warning, once, until it is back
//! under. In a game, going over will be the hard limit made in its build, which isn't built yet.
const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const GPUAllocator = @import("GPUAllocator.zig");

const TargetPlatforms = @This();

/// The most platforms a project has
pub const MAX_PLATFORMS = 8;
/// The longest a name is, in bytes. A longer one is cut short
pub const MAX_NAME_LEN = 32;
const BYTES_PER_MB: u64 = 1024 * 1024;

const Name = struct {
    mBytes: [MAX_NAME_LEN]u8 = @splat(0),
    mLen: u8 = 0,

    fn Of(text: []const u8) Name {
        var name: Name = .{};
        const len = CutLength(text);
        name.mLen = @intCast(len);
        @memcpy(name.mBytes[0..len], text[0..len]);
        return name;
    }

    fn Text(self: *const Name) []const u8 {
        return self.mBytes[0..self.mLen];
    }
};

pub const Platform = struct {
    mName: Name = .{},
    /// budgets, in MB
    mCPUMemoryMB: u32 = 0,
    mVideoMemoryMB: u32 = 0,
};

/// What a new project has
const DEFAULT_PLATFORM = Platform{ .mName = Name.Of("PC"), .mCPUMemoryMB = 8192, .mVideoMemoryMB = 4096 };

/// What the game is using, to set against a budget
pub const Usage = struct {
    CPU: u64 = 0,
    Video: u64 = 0,
};

mPlatforms: [MAX_PLATFORMS]Platform = [_]Platform{DEFAULT_PLATFORM} ++ @as([MAX_PLATFORMS - 1]Platform, @splat(.{})),
mCount: usize = 1,
/// The one the editor checks against
mTarget: usize = 0,
/// Goes up whenever a platform changes, so what shows them can tell it has to show them again
mVersion: u32 = 0,
/// The last usage Check was given, for the Profiler window to show against the budgets
mLastUsage: Usage = .{},
/// Whether the last Check found each budget gone over, so it warns once when it goes over, not every time
mOverCPU: bool = false,
mOverVideo: bool = false,

pub const empty: TargetPlatforms = .{};

pub fn Count(self: *const TargetPlatforms) usize {
    return self.mCount;
}

pub fn Get(self: *const TargetPlatforms, index: usize) *const Platform {
    std.debug.assert(index < self.mCount);
    return &self.mPlatforms[index];
}

pub fn GetName(self: *const TargetPlatforms, index: usize) []const u8 {
    return self.Get(index).mName.Text();
}

pub fn Target(self: *const TargetPlatforms) *const Platform {
    return self.Get(self.mTarget);
}

/// Renames a platform. An empty name is left as it was, and one longer than MAX_NAME_LEN is cut short, never part way
/// through a character
pub fn SetName(self: *TargetPlatforms, index: usize, text: []const u8) void {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed[0..CutLength(trimmed)], self.GetName(index))) return;
    self.mPlatforms[index].mName = Name.Of(trimmed);
    self.mVersion +%= 1;
}

pub fn SetCPUMemoryMB(self: *TargetPlatforms, index: usize, mb: u32) void {
    std.debug.assert(index < self.mCount);
    self.mPlatforms[index].mCPUMemoryMB = mb;
    self.mVersion +%= 1;
}

pub fn SetVideoMemoryMB(self: *TargetPlatforms, index: usize, mb: u32) void {
    std.debug.assert(index < self.mCount);
    self.mPlatforms[index].mVideoMemoryMB = mb;
    self.mVersion +%= 1;
}

/// Makes a platform the one the editor checks against
pub fn SetTarget(self: *TargetPlatforms, index: usize) void {
    std.debug.assert(index < self.mCount);
    self.mTarget = index;
    self.mOverCPU = false;
    self.mOverVideo = false;
    self.mVersion +%= 1;
}

/// A new platform on the end, with the budgets a new project's has
pub fn Add(self: *TargetPlatforms) !void {
    if (self.mCount == MAX_PLATFORMS) return error.TooManyPlatforms;
    var platform = DEFAULT_PLATFORM;
    var number: [16]u8 = undefined;
    platform.mName = Name.Of(try std.fmt.bufPrint(&number, "Platform {d}", .{self.mCount + 1}));
    self.mPlatforms[self.mCount] = platform;
    self.mCount += 1;
    self.mVersion +%= 1;
}

/// Takes a platform out, those after it moving up. The last one left can't go: there is always a target
pub fn Remove(self: *TargetPlatforms, index: usize) !void {
    std.debug.assert(index < self.mCount);
    if (self.mCount == 1) return error.LastPlatform;
    std.mem.copyForwards(Platform, self.mPlatforms[index .. self.mCount - 1], self.mPlatforms[index + 1 .. self.mCount]);
    self.mCount -= 1;
    self.mPlatforms[self.mCount] = .{};
    if (self.mTarget > index or self.mTarget == self.mCount) self.mTarget -|= 1;
    self.mVersion +%= 1;
}

/// The game's memory as near as the editor can tell: `game_world` (the Game world, or the Simulate world while playing)
/// and the objects loaded from files (the Asset world). The engine's shared memory is left out, being mixed with the
/// editor's own. Video: the world's render targets and atlas slots, and the loaded textures' slots, the engine's, which
/// has the editor's own icons in it too, so it reads a little high
pub fn EditorUsage(engine_context: *EngineContext, game_world: *WorldManager) Usage {
    const gpu = &engine_context.mGPUAllocator;
    const owner = engine_context.WorldTag(game_world);
    return .{
        .CPU = @intCast(game_world.mMemory.Totals().Bytes() + engine_context.mAssetWorld.mMemory.Totals().Bytes()),
        .Video = gpu.CountsOf(owner).Bytes + gpu.AtlasBytesOf(owner) + gpu.AtlasBytesOf(GPUAllocator.ENGINE),
    };
}

/// A game's memory, all of it: the whole application's, and the video memory the driver counts it holding (what the
/// engine made, if the driver can't be asked)
pub fn GameUsage(engine_context: *EngineContext) Usage {
    const gpu = &engine_context.mGPUAllocator;
    const video = if (gpu.mDriver.Read()) |driver| driver.Used + driver.Shared else gpu.TotalBytes();
    return .{ .CPU = @intCast(engine_context._Internal.Memory.Root().Totals().Bytes()), .Video = video };
}

/// Sets `usage` against the target's budgets, warning when one is gone over: once, then again only after it has been
/// back under
pub fn Check(self: *TargetPlatforms, usage: Usage) void {
    self.mLastUsage = usage;
    const target = self.Target();
    CheckOne(&self.mOverCPU, "CPU memory", target, usage.CPU, target.mCPUMemoryMB);
    CheckOne(&self.mOverVideo, "Video memory", target, usage.Video, target.mVideoMemoryMB);
}

fn CheckOne(over: *bool, what: []const u8, target: *const Platform, bytes: u64, budget_mb: u32) void {
    const budget = @as(u64, budget_mb) * BYTES_PER_MB;
    const now_over = bytes > budget;
    if (now_over and !over.*) {
        std.log.warn("{s} is over {s}'s budget: {d} MB of {d} MB", .{ what, target.mName.Text(), bytes / BYTES_PER_MB, budget_mb });
    }
    over.* = now_over;
}

/// How much of `text` fits in a name: all of it, or as much as fits without splitting a UTF-8 character
fn CutLength(text: []const u8) usize {
    if (text.len <= MAX_NAME_LEN) return text.len;
    var len: usize = MAX_NAME_LEN;
    //a byte 10xxxxxx continues the character before it
    while (len > 0 and text[len] & 0xC0 == 0x80) len -= 1;
    return len;
}

//=========================================== PROJECT SETTINGS ===========================================

pub const ProjectSettingsName = "Platforms";

const SettingsPlatform = struct {
    Name: []const u8 = "",
    CPUMemoryMB: u32 = DEFAULT_PLATFORM.mCPUMemoryMB,
    VideoMemoryMB: u32 = DEFAULT_PLATFORM.mVideoMemoryMB,
};

const SettingsFile = struct {
    Platforms: []const SettingsPlatform = &.{},
    /// the target's name
    Target: []const u8 = "",
};

pub fn SaveProjectSettings(self: *TargetPlatforms, _: *EngineContext, write_stream: *std.json.Stringify) !void {
    var platforms: [MAX_PLATFORMS]SettingsPlatform = undefined;
    for (platforms[0..self.mCount], self.mPlatforms[0..self.mCount]) |*saved, *platform| {
        saved.* = .{ .Name = platform.mName.Text(), .CPUMemoryMB = platform.mCPUMemoryMB, .VideoMemoryMB = platform.mVideoMemoryMB };
    }
    try write_stream.write(SettingsFile{ .Platforms = platforms[0..self.mCount], .Target = self.Target().mName.Text() });
}

/// The platforms in the settings, and the target by its name. None in them leaves a new project's
pub fn LoadProjectSettings(self: *TargetPlatforms, engine_context: *EngineContext, scanner: *std.json.Scanner) !void {
    try self.ResetProjectSettings(engine_context);
    const settings = try std.json.innerParse(SettingsFile, engine_context.Scratch(), scanner, .{
        .allocate = .alloc_always,
        .max_value_len = std.json.default_max_value_len,
        .ignore_unknown_fields = true,
    });
    if (settings.Platforms.len == 0) return;
    self.mCount = @min(settings.Platforms.len, MAX_PLATFORMS);
    for (settings.Platforms[0..self.mCount], 0..) |saved, index| {
        self.mPlatforms[index] = .{ .mName = Name.Of(if (saved.Name.len > 0) saved.Name else "Platform"), .mCPUMemoryMB = saved.CPUMemoryMB, .mVideoMemoryMB = saved.VideoMemoryMB };
        if (std.mem.eql(u8, saved.Name, settings.Target)) self.mTarget = index;
    }
    self.mVersion +%= 1;
}

/// Back to a new project's one platform
pub fn ResetProjectSettings(self: *TargetPlatforms, _: *EngineContext) !void {
    const version = self.mVersion;
    self.* = .empty;
    self.mVersion = version +% 1;
}
//========================================= END PROJECT SETTINGS =========================================
