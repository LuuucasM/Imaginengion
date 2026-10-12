//! A script file, built into a DLL and loaded. The DLL hands back a ScriptInfo (see Scripts/ScriptABI.zig): which object
//! type the script goes on, its hooks, and its variables. Every script child running this script has an instance of the
//! variables, kept in the DLL by an instance id handed out here (ScriptComponent.mInstance).
//! When the file changes it is built again and swapped in place (Reload), the instances carried over by variable name. A
//! script that no longer compiles keeps running the last version that did.
const std = @import("std");
const builtin = @import("builtin");
const ScriptAsset = @This();

const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptValues = @import("../../Scripts/ScriptValues.zig");
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

pub fn Init(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {
    const zone = Tracy.ZoneInit("ScriptAsset::Init", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    try Lib.Build(engine_context, abs_path, rel_path);
    self._Info = try self._Lib.Open(engine_context, abs_path, 0);
}

pub fn Deinit(self: *ScriptAsset, engine_context: *EngineContext) void {
    //every script child gives its instance back first (ScriptComponent.Deinit holds a reference to this asset)
    if (self._Info) |info| info.mDeinit(engine_context);
    self._Lib.Close(engine_context);
    self._Live.deinit(engine_context.EngineAllocator());
}

/// Builds the file again and swaps the new build in, every instance carried over by variable name: a variable that is
/// still there with the same kind keeps its value, a new one starts at its default. False, with the old build still
/// running, if the new one doesn't build or load (why is logged)
pub fn Reload(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8) !bool {
    const zone = Tracy.ZoneInit("ScriptAsset::Reload", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    Lib.Build(engine_context, abs_path, rel_path) catch |err| switch (err) {
        error.AssetInitFailed => {
            std.log.err("{s} didn't build, it keeps running the last version that did", .{rel_path});
            return false;
        },
        else => return err,
    };
    var new_lib: Lib = .{};
    const new_info = new_lib.Open(engine_context, abs_path, self.mGeneration + 1) catch |err| switch (err) {
        error.AssetInitFailed => {
            std.log.err("{s} didn't load, it keeps running the last version that did", .{rel_path});
            return false;
        },
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

    old_info.mDeinit(engine_context);
    self._Lib.Close(engine_context);
    self._Lib = new_lib;
    self._Info = new_info;
    self.mGeneration += 1;
    return true;
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
