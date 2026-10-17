//! The names of the collision layers, the bits of a collider's CollisionFilter masks. Physics only ever sees the bits:
//! the names are for the editor, shown on a collider's checkboxes and renamed in the Collision Layer Names panel.
//! A new project's names are the layers' numbers, "1" to "32". Kept per project, in ProjectSettings/CollisionLayers.json
//! (see Project.zig)
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

const CollisionLayers = @This();

/// How many layers there are, one per bit of a CollisionFilter mask
pub const COUNT = 32;
/// The longest a name is, in bytes. A longer one is cut short
pub const MAX_NAME_LEN = 32;

const Name = struct {
    mBytes: [MAX_NAME_LEN]u8 = @splat(0),
    mLen: u8 = 0,

    fn Of(text: []const u8) Name {
        var name: Name = .{};
        name.mLen = @intCast(text.len);
        @memcpy(name.mBytes[0..text.len], text);
        return name;
    }
};

/// Each layer's number, from 1
const DEFAULT_NAMES = blk: {
    @setEvalBranchQuota(20_000);
    var names: [COUNT]Name = undefined;
    for (&names, 0..) |*name, layer| name.* = Name.Of(std.fmt.comptimePrint("{d}", .{layer + 1}));
    break :blk names;
};

mNames: [COUNT]Name = DEFAULT_NAMES,
/// Goes up whenever a name changes, so what shows the names can tell it has to show them again
mVersion: u32 = 0,

/// The name of the layer that is bit `layer` of a mask
pub fn GetName(self: *const CollisionLayers, layer: usize) []const u8 {
    const name = &self.mNames[layer];
    return name.mBytes[0..name.mLen];
}

/// Renames the layer that is bit `layer` of a mask. An empty name puts its number back, and one longer than
/// MAX_NAME_LEN is cut short, never part way through a character
pub fn SetName(self: *CollisionLayers, layer: usize, text: []const u8) void {
    const trimmed = std.mem.trim(u8, text, " \t");
    const name = if (trimmed.len == 0) DEFAULT_NAMES[layer] else Name.Of(trimmed[0..CutLength(trimmed)]);
    if (std.mem.eql(u8, name.mBytes[0..name.mLen], self.GetName(layer))) return;
    self.mNames[layer] = name;
    self.mVersion +%= 1;
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

pub const ProjectSettingsName = "CollisionLayers";

const SettingsFile = struct {
    /// every layer's name, in bit order
    Names: []const []const u8 = &.{},
};

pub fn SaveProjectSettings(self: *CollisionLayers, _: *EngineContext, write_stream: *std.json.Stringify) !void {
    var names: [COUNT][]const u8 = undefined;
    for (&names, 0..) |*name, layer| name.* = self.GetName(layer);
    try write_stream.write(SettingsFile{ .Names = &names });
}

/// The names in the settings. A layer the settings have no name for gets its number
pub fn LoadProjectSettings(self: *CollisionLayers, engine_context: *EngineContext, scanner: *std.json.Scanner) !void {
    try self.ResetProjectSettings(engine_context);
    const settings = try std.json.innerParse(SettingsFile, engine_context.FrameAllocator(), scanner, .{
        .allocate = .alloc_always,
        .max_value_len = std.json.default_max_value_len,
    });
    for (settings.Names[0..@min(settings.Names.len, COUNT)], 0..) |name, layer| self.SetName(layer, name);
}

/// Back to a new project's names, the layers' numbers
pub fn ResetProjectSettings(self: *CollisionLayers, _: *EngineContext) !void {
    self.mNames = DEFAULT_NAMES;
    self.mVersion +%= 1;
}
//========================================= END PROJECT SETTINGS =========================================
