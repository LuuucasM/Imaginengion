//! One value of an enum the game defines in a project .zig file (see EnumAsset): game data like a game's state, kept on
//! an object for its scripts to read and change, the way an AttribComponent keeps a number.
//!     //GameState.zig
//!     pub const GameState = enum { Playing, Paused, GameOver };
//!     //a script
//!     const GameState = @import("GameState").GameState;
//!     if (state.Get(GameState) == .Paused) ...
//!     try state.Set(GameState.Playing);
//! The value and the enum are kept by name, so reordering or adding values never changes what it holds, and a built game
//! needs neither the file nor parsing it. The file is only the editor's, for the dropdown of values
const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const EnumAsset = @import("../Asset/EnumAsset.zig");

const EnumComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "EnumComponent";

/// The longest an enum's or a value's name can be, in bytes
pub const MAX_NAME_LEN = 64;

/// A name kept in the component itself, so it never allocates and copies with it
const ShortName = struct {
    mBytes: [MAX_NAME_LEN]u8 = @splat(0),
    mLen: u8 = 0,

    fn Get(self: *const ShortName) []const u8 {
        return self.mBytes[0..self.mLen];
    }

    fn Set(self: *ShortName, text: []const u8) error{NameTooLong}!void {
        if (text.len > MAX_NAME_LEN) return error.NameTooLong;
        self.* = .{};
        @memcpy(self.mBytes[0..text.len], text);
        self.mLen = @intCast(text.len);
    }
};

/// The .zig file the enum is in, for the editor's dropdown of its values
mEnumFile: AssetHandle = .uninit,
/// The enum's name, its file's name: which enum Get and Set take
mEnumName: ShortName = .{},
/// The value's name, empty for none picked yet
mValue: ShortName = .{},

pub fn Deinit(self: *EnumComponent, _: *EngineContext) void {
    self.mEnumFile.ReleaseAsset();
}

pub fn Clone(self: *const EnumComponent, _: *EngineContext) !EnumComponent {
    //the copy releases the file itself, so it needs its own reference
    self.mEnumFile.RetainAsset();
    return self.*;
}

/// The enum's name, empty while no file is set
pub fn GetEnumName(self: *const EnumComponent) []const u8 {
    return self.mEnumName.Get();
}

/// The value's name, empty while none is picked
pub fn GetName(self: *const EnumComponent) []const u8 {
    return self.mValue.Get();
}

/// The value as the enum T (the enum from the file, e.g. @import("GameState").GameState). Null if it holds another
/// enum, or a name T hasn't (none picked yet, or a value renamed or removed since)
pub fn Get(self: *const EnumComponent, comptime T: type) ?T {
    if (@typeInfo(T) != .@"enum") @compileError("EnumComponent.Get takes the enum type, not " ++ @typeName(T));
    if (!std.mem.eql(u8, self.GetEnumName(), comptime EnumNameOf(T))) return null;
    return std.meta.stringToEnum(T, self.GetName());
}

/// Sets the value to `value`, of the enum from the file. error.WrongEnum if this holds another enum
pub fn Set(self: *EnumComponent, value: anytype) error{ WrongEnum, NameTooLong }!void {
    const T = @TypeOf(value);
    if (@typeInfo(T) != .@"enum") @compileError("EnumComponent.Set takes a value of the enum, not " ++ @typeName(T));
    if (!std.mem.eql(u8, self.GetEnumName(), comptime EnumNameOf(T))) return error.WrongEnum;
    try self.mValue.Set(@tagName(value));
}

/// An enum's name: the last part of its type's name, @import("GameState").GameState's is GameState
fn EnumNameOf(comptime T: type) []const u8 {
    const full = @typeName(T);
    return full[if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot| dot + 1 else 0..];
}

pub fn UIRender(self: *EnumComponent, ui: *Inspector.Builder) !void {
    try ui.Asset(&self.mEnumFile, "Enum", &.{".zig"}, .{ .OnChange = OnEnumFileChanged, .Rebuilds = true });
    if (!self.mEnumFile.IsIDValid()) return;

    //the file's values as they are now: the panel is built again when the file changes
    const enum_asset = try self.mEnumFile.GetAsset(ui.mEngineContext, EnumAsset);
    const value = self.GetName();
    if (value.len > 0 and enum_asset.IndexOf(value) == null) {
        var buffer: [MAX_NAME_LEN * 2 + 32]u8 = undefined;
        try ui.Note(try std.fmt.bufPrint(&buffer, "\"{s}\" is no longer in {s}", .{ value, self.GetEnumName() }));
    }
    //the whole component, since which value is which depends on its file
    try ui.Choice(self, "Value", enum_asset.mNames.items, &VALUE_ACCESS, .{});
}

/// A new file picked: its enum is the one named after it, and a value of the enum that was there means nothing in it
fn OnEnumFileChanged(component: *anyopaque) void {
    const self: *EnumComponent = @ptrCast(@alignCast(component));
    const enum_name = if (self.mEnumFile.IsIDValid()) std.fs.path.stem(self.mEnumFile.GetFileMetaData().mRelPath.items) else "";
    if (std.mem.eql(u8, enum_name, self.GetEnumName())) return;
    self.mEnumName.Set(enum_name) catch {
        std.log.err("An enum's name can be at most {d} characters, {s} is longer", .{ MAX_NAME_LEN, enum_name });
        self.mEnumName = .{};
    };
    self.mValue = .{};
}

/// The value as its place among its file's values, read from the whole component. One that isn't among them (renamed,
/// removed, none picked) is past the end, which the dropdown shows as no choice
const VALUE_ACCESS = Inspector.Access{
    .Read = struct {
        fn Read(field: *anyopaque) Inspector.Value {
            const self: *const EnumComponent = @ptrCast(@alignCast(field));
            const enum_asset = LoadedEnumAsset(self) orelse return .{ .Choice = std.math.maxInt(usize) };
            return .{ .Choice = enum_asset.IndexOf(self.GetName()) orelse std.math.maxInt(usize) };
        }
    }.Read,
    .Write = struct {
        fn Write(_: *EngineContext, field: *anyopaque, written: Inspector.Value) anyerror!void {
            const self: *EnumComponent = @ptrCast(@alignCast(field));
            const enum_asset = LoadedEnumAsset(self) orelse return;
            if (written.Choice >= enum_asset.mNames.items.len) return;
            const name = enum_asset.mNames.items[written.Choice];
            self.mValue.Set(name) catch std.log.err("A value's name can be at most {d} characters, {s} is longer", .{ MAX_NAME_LEN, name });
        }
    }.Write,
};

fn LoadedEnumAsset(self: *const EnumComponent) ?*EnumAsset {
    if (!self.mEnumFile.IsIDValid()) return null;
    return self.mEnumFile.mManager.GetLoadedAsset(EnumAsset, self.mEnumFile.mID);
}

const Saved = struct {
    EnumFile: AssetHandle = .uninit,
    Enum: []const u8 = "",
    Value: []const u8 = "",
};

pub fn jsonStringify(self: *const EnumComponent, jw: anytype) !void {
    try jw.write(Saved{ .EnumFile = self.mEnumFile, .Enum = self.GetEnumName(), .Value = self.GetName() });
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!EnumComponent {
    const saved = try std.json.innerParse(Saved, frame_allocator, reader, options);
    var component = EnumComponent{ .mEnumFile = saved.EnumFile };
    //a name too long for the component was never saved by it: a hand edit, left empty
    component.mEnumName.Set(saved.Enum) catch {};
    component.mValue.Set(saved.Value) catch {};
    return component;
}
