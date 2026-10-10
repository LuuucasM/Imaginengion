const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const PathType = @import("../../ECSManagers/AManager.zig").PathType;
const Vec4 = @import("../../Math/MathTypes.zig").Vec4;
const TextAsset = @import("TextAsset.zig");
const ThemeAsset = @This();

pub const Name: []const u8 = "ThemeAsset";

/// The colors one part of an element takes in each state its entity can be in (see StyleSystem). A state left null
/// takes the Normal color, and Normal left null leaves that part of the entity alone
pub const StateColors = struct {
    Normal: ?Vec4(f32) = null,
    Hovered: ?Vec4(f32) = null,
    Pressed: ?Vec4(f32) = null,
    Focused: ?Vec4(f32) = null,
    Selected: ?Vec4(f32) = null,
    Disabled: ?Vec4(f32) = null,
};

/// A theme's sizes (BorderWidth, CornerRadius, FontSize) are in overlay units, about a pixel each. In a game scene one
/// of them is this many world units, so text at a theme's usual 16 is one world unit tall (StyleSystem.ThemeUnit)
pub const GAME_LAYER_UNIT: f32 = 1.0 / 16.0;

/// In a game's overlay (one that scales with the screen, 1080 units tall) one of a theme's sizes is this many overlay
/// units, so text at a theme's usual 16 starts at 48, menu sized instead of editor sized (StyleSystem.ThemeUnit)
pub const GAME_OVERLAY_UNIT: f32 = 3.0;

/// How an element with this style (StyleComponent) looks. Everything is optional: whatever a style leaves out is left
/// as the entity has it
pub const Style = struct {
    /// the entity's quad
    Background: StateColors = .{},
    /// the band around the edge of the quad, BorderWidth wide
    Border: StateColors = .{},
    /// the entity's text
    Text: StateColors = .{},
    BorderWidth: ?f32 = null,
    /// every corner of the quad rounded by this much
    CornerRadius: ?f32 = null,
    /// the text's font. uninit leaves it as it is
    Font: AssetHandle = .uninit,
    FontSize: ?f32 = null,
};

/// A theme file (.imtheme, JSON): a set of named styles that UI elements pick from by name. One theme is current at a
/// time (UIManager.SetTheme), and a theme file changed on disk is read again while the engine runs. E.g.
///     { "Styles": { "Button": { "Background": { "Normal": [0.25, 0.27, 0.36, 1], "Hovered": [0.38, 0.4, 0.54, 1] },
///                               "CornerRadius": 4,
///                               "Font": { "Path": "src/.../ChironGoRoundTC-Bold.ttf", "PathType": "Eng" } } } }
/// Colors are [r, g, b, a] from 0 to 1. A font's path is relative to the engine (Eng) or to the project (Prj)
mStyles: std.StringArrayHashMapUnmanaged(Style) = .empty,

//what the file holds, before its fonts are turned into asset handles
const FileColors = struct {
    Normal: ?[4]f32 = null,
    Hovered: ?[4]f32 = null,
    Pressed: ?[4]f32 = null,
    Focused: ?[4]f32 = null,
    Selected: ?[4]f32 = null,
    Disabled: ?[4]f32 = null,
};
const FileFont = struct {
    Path: []const u8,
    PathType: PathType = .Eng,
};
const FileStyle = struct {
    Background: FileColors = .{},
    Border: FileColors = .{},
    Text: FileColors = .{},
    BorderWidth: ?f32 = null,
    CornerRadius: ?f32 = null,
    Font: ?FileFont = null,
    FontSize: ?f32 = null,
};
const File = struct {
    Styles: std.json.ArrayHashMap(FileStyle) = .{},
};

pub fn Init(self: *ThemeAsset, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    var file_reader = asset_file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.FrameAllocator(), .unlimited);
    self.FromJson(engine_context, contents) catch |err| {
        std.log.err("Theme {s} could not be read: {s}", .{ rel_path, @errorName(err) });
        self.Deinit(engine_context);
        return error.AssetInitFailed;
    };
    self.LoadFonts(engine_context);
}

/// Reads every font the theme's styles use now, while the theme is being read: left until something is first drawn with
/// one, that frame would wait on it (a big font takes about 100 ms). A font that can't be read is logged and left to
/// the text drawing it, as before
fn LoadFonts(self: *ThemeAsset, engine_context: *EngineContext) void {
    for (self.mStyles.values()) |style| {
        if (!style.Font.IsIDValid()) continue;
        _ = style.Font.GetAsset(engine_context, TextAsset) catch |err| {
            std.log.err("A theme font could not be read: {s}", .{@errorName(err)});
        };
    }
}

/// Reads a theme's styles from the text of a theme file
pub fn FromJson(self: *ThemeAsset, engine_context: *EngineContext, contents: []const u8) !void {
    const engine_allocator = engine_context.EngineAllocator();
    const file = try std.json.parseFromSliceLeaky(File, engine_context.FrameAllocator(), contents, .{});

    var iter = file.Styles.map.iterator();
    while (iter.next()) |entry| {
        const file_style = entry.value_ptr.*;
        var style = Style{
            .Background = ToStateColors(file_style.Background),
            .Border = ToStateColors(file_style.Border),
            .Text = ToStateColors(file_style.Text),
            .BorderWidth = file_style.BorderWidth,
            .CornerRadius = file_style.CornerRadius,
            .FontSize = file_style.FontSize,
        };
        if (file_style.Font) |font| {
            style.Font = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = font.Path, .path_type = font.PathType } });
        }
        errdefer style.Font.ReleaseAsset();

        const name = try engine_allocator.dupe(u8, entry.key_ptr.*);
        errdefer engine_allocator.free(name);
        try self.mStyles.put(engine_allocator, name, style);
    }
}

pub fn Deinit(self: *ThemeAsset, engine_context: *EngineContext) void {
    const engine_allocator = engine_context.EngineAllocator();
    var iter = self.mStyles.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.Font.ReleaseAsset();
        engine_allocator.free(entry.key_ptr.*);
    }
    self.mStyles.deinit(engine_allocator);
}

/// The style called `name`, null if the theme has none by that name
pub fn GetStyle(self: *const ThemeAsset, name: []const u8) ?*const Style {
    return self.mStyles.getPtr(name);
}

fn ToStateColors(colors: FileColors) StateColors {
    return .{
        .Normal = ToColor(colors.Normal),
        .Hovered = ToColor(colors.Hovered),
        .Pressed = ToColor(colors.Pressed),
        .Focused = ToColor(colors.Focused),
        .Selected = ToColor(colors.Selected),
        .Disabled = ToColor(colors.Disabled),
    };
}

fn ToColor(color: ?[4]f32) ?Vec4(f32) {
    const c = color orelse return null;
    return .{ .x = c[0], .y = c[1], .z = c[2], .w = c[3] };
}
