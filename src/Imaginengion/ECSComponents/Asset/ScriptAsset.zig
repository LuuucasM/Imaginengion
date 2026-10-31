//! A script file, built into a DLL and loaded. The DLL hands back a ScriptInfo (see Scripts/ScriptABI.zig): which object
//! type the script goes on, its hooks, and its variables. Every script child running this script has an instance of the
//! variables, kept in the DLL by an instance id handed out here (ScriptComponent.mInstance).
//! When the file changes it is built again and swapped in place (Reload), the instances carried over by variable name. A
//! script that no longer compiles keeps running the last version that did.
//! It is built again too when a project file it imports changes (its dependencies, from the DLL, which this holds asset
//! handles to so the asset manager watches them). If that build fails the script stops (mStopped) rather than keep
//! running: its old build was made with the old file, and a game event is only understood the same way by every script
//! when they are all built with the same version of it (see Scripts/GameEvents.zig)
const std = @import("std");
const builtin = @import("builtin");
const ScriptAsset = @This();

const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptValues = @import("../../Scripts/ScriptValues.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const ScriptInfo = ScriptABI.ScriptInfo;
const Hook = ScriptABI.Hook;

pub const ScriptResult = ScriptABI.ScriptResult;

const Lib = switch (builtin.os.tag) {
    .windows => @import("ScriptAssets/WindowsScriptAsset.zig"),
    else => @import("ScriptAssets/OtherScriptAsset.zig"),
};

pub const Name: []const u8 = "ScriptAsset";

_Lib: Lib = .{},
_Info: ?*const ScriptInfo = null,
/// which instance ids are in use, so a new one gets a free id and a reload knows which to carry over
_Live: std.DynamicBitSetUnmanaged = .{},
/// goes up each time the script is swapped for a new build, which can move its variables: what was built from the old
/// variable table (the Scripts panel's fields) checks it to know to build again
mGeneration: u32 = 0,
/// a file it imports changed and it didn't build after: nothing of it runs until it does
mStopped: bool = false,
/// the project files it imports, as file-only assets so the asset manager watches them
_Dependencies: std.ArrayList(AssetHandle) = .empty,

pub fn Init(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {
    const zone = Tracy.ZoneInit("ScriptAsset::Init", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    try Lib.Build(engine_context, abs_path, rel_path);
    self._Info = try self._Lib.Open(engine_context, abs_path, 0);
    try self.WatchDependencies(engine_context);
}

pub fn Deinit(self: *ScriptAsset, engine_context: *EngineContext) void {
    //every script child gives its instance back first (ScriptComponent.Deinit holds a reference to this asset)
    if (self._Info) |info| info.mDeinit(engine_context);
    self._Lib.Close(engine_context);
    self._Live.deinit(engine_context.EngineAllocator());
    self.ReleaseDependencies(engine_context);
}

/// Builds the file again and swaps the new build in, every instance carried over by variable name: a variable that is
/// still there with the same kind keeps its value, a new one starts at its default. False if the new one doesn't build
/// or load (why is logged): the old build keeps running, unless `for_import` (a file it imports changed), when it
/// stops until a build works (mStopped)
pub fn Reload(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, for_import: bool) !bool {
    const zone = Tracy.ZoneInit("ScriptAsset::Reload", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    Lib.Build(engine_context, abs_path, rel_path) catch |err| switch (err) {
        error.AssetInitFailed => return self.Failed(rel_path, "build", for_import),
        else => return err,
    };
    var new_lib: Lib = .{};
    const new_info = new_lib.Open(engine_context, abs_path, self.mGeneration + 1) catch |err| switch (err) {
        error.AssetInitFailed => return self.Failed(rel_path, "load", for_import),
        else => return err,
    };
    const old_info = self._Info.?;

    var live = self._Live.iterator(.{});
    while (live.next()) |index| {
        const id: u32 = @intCast(index);
        if (!new_info.mNewInstance(engine_context, id, null)) {
            //out of memory part way through: the new build goes and the old one stays as it was
            var made = self._Live.iterator(.{});
            while (made.next()) |made_index| {
                if (made_index >= index) break;
                new_info.mFreeInstance(engine_context, @intCast(made_index));
            }
            new_info.mDeinit(engine_context);
            new_lib.Close(engine_context);
            return error.OutOfMemory;
        }
        ScriptValues.CarryOver(old_info, old_info.mGetInstance(id).?, new_info, new_info.mGetInstance(id).?);
    }

    //only now that nothing can turn the new build down
    live = self._Live.iterator(.{});
    while (live.next()) |index| ScriptValues.ReleaseDropped(old_info, old_info.mGetInstance(@intCast(index)).?, new_info);

    old_info.mDeinit(engine_context);
    self._Lib.Close(engine_context);
    self._Lib = new_lib;
    self._Info = new_info;
    self.mGeneration += 1;
    if (self.mStopped) std.log.info("{s} builds again, so it runs again", .{rel_path});
    self.mStopped = false;
    //what it imports can be different now
    try self.WatchDependencies(engine_context);
    return true;
}

/// A reload that didn't build or load. A script already stopped stays stopped: its old build is still the stale one
fn Failed(self: *ScriptAsset, rel_path: []const u8, comptime what: []const u8, for_import: bool) bool {
    if (for_import or self.mStopped) {
        self.mStopped = true;
        std.log.err("{s} didn't " ++ what ++ " after a file it imports changed: it stops until it builds, so it never runs with an old version of that file", .{rel_path});
    } else {
        std.log.err("{s} didn't " ++ what ++ ", it keeps running the last version that did", .{rel_path});
    }
    return false;
}

/// Whether a project file it imports changed last frame (see FileChangedTag)
pub fn DependencyChanged(self: *const ScriptAsset, engine_context: *EngineContext) bool {
    for (self._Dependencies.items) |dependency| {
        if (engine_context.mAssetManager.FileChanged(dependency.mID)) return true;
    }
    return false;
}

/// Holds an asset handle for each project file the loaded build imports, in place of the last build's
fn WatchDependencies(self: *ScriptAsset, engine_context: *EngineContext) !void {
    self.ReleaseDependencies(engine_context);
    const asset_manager = &engine_context.mAssetManager;
    for (self.GetInfo().Dependencies()) |dependency| {
        const abs_path = std.mem.span(dependency);
        //what the build finds is in the project, imported by name or next to such a file: anything else is left alone
        const rel_path = InProject(engine_context, abs_path) orelse continue;
        const handle = asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Prj } }) catch |err| {
            std.log.warn("couldn't watch {s}, a file a script imports: {s}", .{ abs_path, @errorName(err) });
            continue;
        };
        try self._Dependencies.append(engine_context.EngineAllocator(), handle);
    }
}

/// `abs_path` from the open project's folder, null if it isn't in it. Either slash counts as a separator: the build
/// writes paths its own way
fn InProject(engine_context: *EngineContext, abs_path: []const u8) ?[]const u8 {
    const project = &engine_context.mProject;
    if (!project.IsOpen()) return null;
    const folder = project.mPath.items;
    if (abs_path.len <= folder.len + 1) return null;
    for (folder, abs_path[0..folder.len]) |a, b| {
        const same = std.ascii.toLower(a) == std.ascii.toLower(b) or (IsSeparator(a) and IsSeparator(b));
        if (!same) return null;
    }
    if (!IsSeparator(abs_path[folder.len])) return null;
    return abs_path[folder.len + 1 ..];
}

fn IsSeparator(c: u8) bool {
    return c == '/' or c == '\\';
}

fn ReleaseDependencies(self: *ScriptAsset, engine_context: *EngineContext) void {
    for (self._Dependencies.items) |*dependency| dependency.ReleaseAsset();
    self._Dependencies.deinit(engine_context.EngineAllocator());
    self._Dependencies = .empty;
}

pub fn GetInfo(self: *const ScriptAsset) *const ScriptInfo {
    return self._Info.?;
}

/// The object type the script goes on
pub fn GetOwner(self: *const ScriptAsset) ScriptABI.OwnerKind {
    return self.GetInfo().mOwner;
}

pub fn HasHook(self: *const ScriptAsset, hook: Hook) bool {
    return self.GetInfo().HasHook(hook);
}

/// A new instance of the script's variables: a copy of instance `copy_from`'s, or the script's defaults when null
pub fn NewInstance(self: *ScriptAsset, engine_context: *EngineContext, copy_from: ?u32) !u32 {
    const engine_allocator = engine_context.EngineAllocator();
    var free_ids = self._Live.iterator(.{ .kind = .unset });
    const id = free_ids.next() orelse blk: {
        const old_len = self._Live.bit_length;
        try self._Live.resize(engine_allocator, @max(16, old_len * 2), false);
        break :blk old_len;
    };
    self._Live.set(id);
    errdefer self._Live.unset(id);

    const from: ?*const anyopaque = if (copy_from) |from_id| self.GetInstance(from_id) else null;
    if (!self.GetInfo().mNewInstance(engine_context, @intCast(id), from)) return error.OutOfMemory;
    return @intCast(id);
}

pub fn FreeInstance(self: *ScriptAsset, engine_context: *EngineContext, id: u32) void {
    self.GetInfo().mFreeInstance(engine_context, id);
    self._Live.unset(id);
}

/// Where instance `id`'s variables are, until it is freed or the script is swapped for a new build (Reload)
pub fn GetInstance(self: *const ScriptAsset, id: u32) ?*anyopaque {
    return self.GetInfo().mGetInstance(id);
}

/// Runs the script's `hook` on an owner of type ObjectType. `args` is (engine context, owner pointer, instance) then the
/// hook's own parameters, see ScriptABI.HookFn. The script has to have the hook
pub fn RunHook(self: *const ScriptAsset, comptime ObjectType: type, comptime hook: Hook, args: anytype) ScriptResult {
    const hook_fn: ScriptABI.HookFn(ObjectType, hook) = @ptrCast(@alignCast(self.GetInfo().mHooks[@intFromEnum(hook)].?));
    return @call(.auto, hook_fn, args);
}

/// Runs one of the script's game event handlers (from its ScriptInfo) on an owner of type ObjectType, with the event's
/// bytes at `event`
pub fn RunHandler(comptime ObjectType: type, handler: *const ScriptABI.EventHandler, engine_context: *EngineContext, owner: *const ObjectType, instance: *anyopaque, event: *const anyopaque) ScriptResult {
    const handler_fn: ScriptABI.HandlerFn(ObjectType) = @ptrCast(@alignCast(handler.mFn));
    return handler_fn(engine_context, owner, instance, event);
}
