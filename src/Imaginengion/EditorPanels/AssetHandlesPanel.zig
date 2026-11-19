//! The Asset Handles panel, in the editor's own UI: a floating window listing every asset the asset manager knows, under
//! a section for each type with how many there are and what they take. Each asset's row has its file, how many handles
//! hold it, whether it is on its way out (failed to load, its file missing, or unused: PendingDelete, with the time left)
//! and what it is: a texture's size and the atlas slot it takes, a sound's length and decoded size, a script's instances,
//! and so on. An asset not read in yet has no type, so it is under Not loaded. The sections are made again whenever an
//! asset comes, goes or is read in; the text is refreshed every REFRESH_SECONDS while the window is open.
//!
//! The Profiler window's Video memory section has the totals; this is where to find which asset takes what.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const AManager = @import("../ECSManagers/AManager.zig");
const Assets = @import("../ECSComponents/AComponents.zig");
const TextureManager = @import("../TextureManager/TextureManager.zig");
const AtlasHandle = @import("../TextureManager/AtlasHandle.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const Bytes = @import("../Core/Allocators.zig").Bytes;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const AssetHandlesPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = -200, .y = 100 };
const SIZE = Vec2(f32){ .x = 640, .y = 420 };

/// How often the text is refreshed, as the Profiler window's is
pub const REFRESH_SECONDS: f32 = 0.25;

/// The sections, in their order
pub const Category = enum {
    Textures,
    Fonts,
    Sounds,
    Scripts,
    Shaders,
    Themes,
    Enums,
    Objects,
    /// not read in yet, or its read failed: its type isn't known
    NotLoaded,

    pub fn Title(self: Category) []const u8 {
        return switch (self) {
            .Textures => "Textures",
            .Fonts => "Fonts",
            .Sounds => "Sounds",
            .Scripts => "Scripts",
            .Shaders => "Shaders",
            .Themes => "Themes",
            .Enums => "Enums",
            .Objects => "Scenes, entities, players and game contexts",
            .NotLoaded => "Not loaded",
        };
    }
};
const CATEGORY_COUNT = std.enums.values(Category).len;

/// An asset's row, and its section
const Row = struct {
    Asset: AssetHandle.Type,
    Category: Category,
    Title: Entity,
};

mWindow: Entity = .uninit,
/// The window's content, where the tree goes
mContent: Entity = .uninit,
/// Made the first time the window is open, and again when the assets or their types change
mTree: ?Entity = null,
/// Each section's title, null for a section with no assets
mSections: [CATEGORY_COUNT]?Entity = @splat(null),
/// A row per asset, by section, each section's in the asset manager's order
mRows: std.ArrayList(Row) = .empty,
/// Since the text was last refreshed. Starts due, so it shows as soon as the window opens
mSinceRefresh: f32 = REFRESH_SECONDS,
mOptions: Widgets.Options = .{},

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !AssetHandlesPanel {
    const zone = Tracy.ZoneInit("AssetHandlesPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Asset Handles", SIZE, AT, options);
    const self = AssetHandlesPanel{ .mWindow = window.Window, .mContent = window.Content, .mOptions = options };
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn Deinit(self: *AssetHandlesPanel, keep_allocator: std.mem.Allocator) void {
    self.mRows.deinit(keep_allocator);
}

pub fn IsOpen(self: AssetHandlesPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: AssetHandlesPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: every REFRESH_SECONDS, the sections made again if the assets or their
/// types changed, and every row's and section's text
pub fn Update(self: *AssetHandlesPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetHandlesPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) {
        self.mSinceRefresh = REFRESH_SECONDS;
        return;
    }
    self.mSinceRefresh += engine_context.mDT;
    if (self.mSinceRefresh < REFRESH_SECONDS) return;
    self.mSinceRefresh = 0;

    const asset_manager = &engine_context.mAssetManager;
    const scratch_allocator = engine_context.ProgramScratch();

    //every asset and its section, by section
    const asset_ids = try asset_manager.GetGroup(scratch_allocator, .{ .Component = Assets.FileMetaData });
    const wanted = try scratch_allocator.alloc(Row, asset_ids.items.len);
    var wanted_len: usize = 0;
    for (std.enums.values(Category)) |category| {
        for (asset_ids.items) |asset_id| {
            if (CategoryOf(asset_manager, asset_id) != category) continue;
            wanted[wanted_len] = .{ .Asset = asset_id, .Category = category, .Title = .uninit };
            wanted_len += 1;
        }
    }
    if (self.mTree == null or !SameRows(self.mRows.items, wanted)) try self.BuildRows(engine_context, wanted);

    var totals: [CATEGORY_COUNT]Total = @splat(.{});
    for (self.mRows.items) |row| {
        var line: std.Io.Writer.Allocating = .init(scratch_allocator);
        try WriteRow(&line.writer, engine_context, row, &totals[@intFromEnum(row.Category)]);
        try WidgetActions.SetText(engine_context, row.Title, line.written());
    }
    for (self.mSections, 0..) |maybe_title, category_ind| {
        const title = maybe_title orelse continue;
        var line: std.Io.Writer.Allocating = .init(scratch_allocator);
        try WriteSection(&line.writer, @enumFromInt(category_ind), totals[category_ind]);
        try WidgetActions.SetText(engine_context, title, line.written());
    }
}

/// What a section's assets add up to
const Total = struct {
    Count: usize = 0,
    /// atlas slots for textures and fonts, decoded samples for sounds
    Bytes: u64 = 0,
    /// script instances
    Instances: usize = 0,
};

/// A section for each type that has assets, open, with a row per asset under it
fn BuildRows(self: *AssetHandlesPanel, engine_context: *EngineContext, wanted: []const Row) !void {
    if (self.mTree) |tree| try Widgets.Remove(engine_context, tree, &.{});
    self.mRows.clearRetainingCapacity();
    self.mSections = @splat(null);
    const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mContent });
    self.mTree = tree;

    var section_content: Entity = .uninit;
    var section_category: ?Category = null;
    for (wanted) |row| {
        if (section_category != row.Category) {
            const section = try Widgets.TreeNode(engine_context, .{ .Entity = tree }, row.Category.Title(), .{ .Open = true, .StockScripts = self.mOptions.StockScripts });
            self.mSections[@intFromEnum(row.Category)] = UIManager.LabelOf(section.Header).?;
            section_content = section.Content.?;
            section_category = row.Category;
        }
        const node = try Widgets.TreeNode(engine_context, .{ .Entity = section_content }, "", .{ .Leaf = true, .StockScripts = self.mOptions.StockScripts });
        try self.mRows.append(engine_context.ProgramKeep(), .{ .Asset = row.Asset, .Category = row.Category, .Title = UIManager.LabelOf(node.Header).? });
    }
}

fn SameRows(have: []const Row, wanted: []const Row) bool {
    if (have.len != wanted.len) return false;
    for (have, wanted) |a, b| {
        if (a.Asset != b.Asset or a.Category != b.Category) return false;
    }
    return true;
}

/// Which section an asset is in: the type it is read in as
fn CategoryOf(asset_manager: *AManager, asset_id: AssetHandle.Type) Category {
    const ecs = &asset_manager.mECSManager;
    if (ecs.HasComponent(Assets.Texture2D, asset_id)) return .Textures;
    if (ecs.HasComponent(Assets.TextAsset, asset_id)) return .Fonts;
    if (ecs.HasComponent(Assets.AudioAsset, asset_id)) return .Sounds;
    if (ecs.HasComponent(Assets.ScriptAsset, asset_id)) return .Scripts;
    if (ecs.HasComponent(Assets.ShaderAsset, asset_id)) return .Shaders;
    if (ecs.HasComponent(Assets.ThemeAsset, asset_id)) return .Themes;
    if (ecs.HasComponent(Assets.EnumAsset, asset_id)) return .Enums;
    inline for (.{ Assets.EntityAsset, Assets.SceneAsset, Assets.PlayerAsset, Assets.GCAsset }) |object_asset| {
        if (ecs.HasComponent(object_asset, asset_id)) return .Objects;
    }
    return .NotLoaded;
}

/// A section's title: its type, how many, and what they add up to
fn WriteSection(writer: *std.Io.Writer, category: Category, total: Total) !void {
    try writer.print("{s}   {d}", .{ category.Title(), total.Count });
    switch (category) {
        .Textures, .Fonts => try writer.print("   {f} in the atlas", .{Bytes{ .mBytes = @intCast(total.Bytes) }}),
        .Sounds => try writer.print("   {f} decoded", .{Bytes{ .mBytes = @intCast(total.Bytes) }}),
        .Scripts => try writer.print("   {d} instances", .{total.Instances}),
        else => {},
    }
}

/// An asset's row: its file, the handles holding it, whether it is on its way out, then what its type says of it,
/// added to its section's total as it goes
fn WriteRow(writer: *std.Io.Writer, engine_context: *EngineContext, row: Row, total: *Total) !void {
    const asset_manager = &engine_context.mAssetManager;
    const ecs = &asset_manager.mECSManager;
    const id = row.Asset;
    total.Count += 1;

    const refs = if (ecs.GetComponent(Assets.AssetMetaData, id)) |meta_data| @atomicLoad(usize, &meta_data.mRefs, .monotonic) else 0;
    try writer.print("{s}   held by {d}", .{ asset_manager.GetFileMetaData(id).mRelPath.items, refs });

    if (ecs.HasComponent(Assets.LoadFailedTag, id)) try writer.writeAll("   failed to load");
    if (ecs.GetComponent(Assets.PendingDelete, id)) |pending| {
        const why = if (pending.mReason & AManager.AssetErrorFlags.FileNotFound != 0) "file missing" else "unused";
        const waited = pending.mTime.durationTo(std.Io.Timestamp.now(engine_context.Io(), .awake)).toNanoseconds();
        const left: f64 = @as(f64, @floatFromInt(@max(0, AManager.ASSET_DELETE_TIMEOUT_NS - waited))) / std.time.ns_per_s;
        try writer.print("   {s}, goes in {d:.1} s", .{ why, left });
    }

    switch (row.Category) {
        .Textures => {
            const texture = asset_manager.GetLoadedAsset(Assets.Texture2D, id).?;
            total.Bytes += try WriteTexture(writer, texture);
        },
        .Fonts => {
            const font = asset_manager.GetLoadedAsset(Assets.TextAsset, id).?;
            try writer.writeAll("   atlas");
            total.Bytes += try WriteTexture(writer, &font.mAtlas);
        },
        .Sounds => {
            const sound = asset_manager.GetLoadedAsset(Assets.AudioAsset, id).?;
            const decoded: u64 = sound.GetSamples().len * @sizeOf(f32);
            const seconds = @as(f64, @floatFromInt(sound.GetFrameCount())) / AudioManager.SAMPLE_RATE;
            try writer.print("   {d:.1} s   {f} decoded", .{ seconds, Bytes{ .mBytes = @intCast(decoded) } });
            total.Bytes += decoded;
        },
        .Scripts => {
            const script = asset_manager.GetLoadedAsset(Assets.ScriptAsset, id).?;
            const instances = script._Live.count();
            try writer.print("   {d} instances", .{instances});
            total.Instances += instances;
        },
        .Themes => try writer.print("   {d} styles", .{asset_manager.GetLoadedAsset(Assets.ThemeAsset, id).?.mStyles.count()}),
        .Enums => try writer.print("   {d} values", .{asset_manager.GetLoadedAsset(Assets.EnumAsset, id).?.mNames.items.len}),
        .Shaders, .Objects, .NotLoaded => {},
    }
}

/// A texture's size and the atlas slot it takes. Returns the slot's bytes
fn WriteTexture(writer: *std.Io.Writer, texture: *Assets.Texture2D) !u64 {
    const handle = texture.GetTextureHandle();
    const slot_bytes = TextureManager.SlotBytes(handle);
    try writer.print("   {d} x {d}   {d} px slot, {f}", .{
        texture.GetWidth(),
        texture.GetHeight(),
        AtlasHandle.SlotSize(AtlasHandle.Class(handle)),
        Bytes{ .mBytes = @intCast(slot_bytes) },
    });
    return slot_bytes;
}
