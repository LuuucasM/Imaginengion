//! An enum's value names, read out of the project .zig file that defines it, for the editor's EnumComponent dropdown.
//! The file holds the enum under its own name, the way a script imports it by the file's name:
//!     //GameState.zig
//!     pub const GameState = enum { Playing, Paused, GameOver };
//! The file is parsed (std.zig.Ast), never compiled, so the enum has to be written out: explicit values and a tag type
//! are fine, one made at compile time (@Type, std.meta.FieldEnum) can't be read. Unloaded when the file changes and read
//! again the next time it is asked for (AComponents.FileUpdateList). Only the editor needs it: an EnumComponent keeps
//! its value and its enum by name, so a built game never parses
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");

const EnumAsset = @This();

pub const Name: []const u8 = "EnumAsset";

/// The value names, in the order they are written. Empty for the default asset
mNames: std.ArrayList([]const u8) = .empty,

pub fn Init(self: *EnumAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    const zone = Tracy.ZoneInit("EnumAsset::Init", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    const frame_allocator = engine_context.FrameAllocator();
    var file_reader = asset_file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(frame_allocator, .unlimited);
    const source = try frame_allocator.dupeSentinel(u8, contents, 0);

    const enum_name = std.fs.path.stem(abs_path);
    const names = ParseNames(frame_allocator, source, enum_name) catch |err| {
        switch (err) {
            error.SyntaxError => std.log.err("{s} has a syntax error, so {s}'s values can't be read", .{ rel_path, enum_name }),
            error.NoSuchEnum => std.log.err("{s} has no pub const {s} = enum {{ ... }}: an enum file holds the enum named after it", .{ rel_path, enum_name }),
            error.NotAnEnum => std.log.err("{s}'s {s} isn't an enum written out as enum {{ ... }}, so its values can't be read", .{ rel_path, enum_name }),
            error.OutOfMemory => return err,
        }
        return error.AssetInitFailed;
    };

    const engine_allocator = engine_context.EngineAllocator();
    errdefer self.Deinit(engine_context);
    try self.mNames.ensureTotalCapacityPrecise(engine_allocator, names.len);
    for (names) |name| self.mNames.appendAssumeCapacity(try engine_allocator.dupe(u8, name));
}

pub fn Deinit(self: *EnumAsset, engine_context: *EngineContext) void {
    const engine_allocator = engine_context.EngineAllocator();
    for (self.mNames.items) |name| engine_allocator.free(name);
    self.mNames.deinit(engine_allocator);
}

/// Where the value called `name` is among the enum's values, null if it has none of that name
pub fn IndexOf(self: *const EnumAsset, name: []const u8) ?usize {
    for (self.mNames.items, 0..) |value_name, i| {
        if (std.mem.eql(u8, value_name, name)) return i;
    }
    return null;
}

pub const ParseError = error{ SyntaxError, NoSuchEnum, NotAnEnum } || std.mem.Allocator.Error;

/// The value names of the top level `pub const <enum_name> = enum { ... }` in `source`, in the order they are written,
/// as slices of `source` (an @"quoted" name without its quotes) in a list from `allocator`. A non-exhaustive enum's `_`
/// isn't a value
pub fn ParseNames(allocator: std.mem.Allocator, source: [:0]const u8, enum_name: []const u8) ParseError![]const []const u8 {
    var tree = try std.zig.Ast.parse(allocator, source, .{});
    defer tree.deinit(allocator);
    if (tree.errors.len > 0) return error.SyntaxError;

    for (tree.rootDecls()) |decl| {
        const var_decl = tree.fullVarDecl(decl) orelse continue;
        if (var_decl.visib_token == null) continue;
        if (!std.mem.eql(u8, tree.tokenSlice(var_decl.ast.mut_token + 1), enum_name)) continue;

        const init_node = var_decl.ast.init_node.unwrap() orelse return error.NotAnEnum;
        var buffer: [2]std.zig.Ast.Node.Index = undefined;
        const container = tree.fullContainerDecl(&buffer, init_node) orelse return error.NotAnEnum;
        if (tree.tokenTag(container.ast.main_token) != .keyword_enum) return error.NotAnEnum;

        var names: std.ArrayList([]const u8) = .empty;
        for (container.ast.members) |member| {
            //a declaration or function inside the enum isn't one of its values
            const field = tree.fullContainerField(member) orelse continue;
            const name = Unquoted(tree.tokenSlice(field.ast.main_token));
            if (std.mem.eql(u8, name, "_")) continue;
            try names.append(allocator, name);
        }
        return try names.toOwnedSlice(allocator);
    }
    return error.NoSuchEnum;
}

/// A name written @"like this" as like this
fn Unquoted(name: []const u8) []const u8 {
    if (name.len >= 3 and name[0] == '@' and name[1] == '"') return name[2 .. name.len - 1];
    return name;
}
