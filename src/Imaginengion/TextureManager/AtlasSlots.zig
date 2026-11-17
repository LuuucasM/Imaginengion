//! Where textures go in the atlas's layers (AtlasHandle): a buddy allocator over each layer, with bins on top of it for
//! the small sizes.
//!
//! The buddy: a layer is a block, which splits into four quarters, each of which splits into four again, down to 256
//! pixels. A size that needs a block takes the smallest free block at least as big, in the lowest layer, and splits it
//! down to its size; freeing one merges it with its three buddies (the quarters of the same block) once they are all
//! free, and so on up. So big blocks come back as soon as what was in them is gone.
//!
//! The bins: the two smallest size classes (64 and 128 pixels) take pages from the buddy, a block 8 x 8 of their slots
//! (512 and 1024 pixels), and cut each into its 64 slots. Taking or freeing a slot is a bit in its page; a page that
//! empties goes back to the buddy. So small textures of one size sit together in few pages instead of being scattered
//! through the layers, which keeps them from stopping big blocks merging back. A bigger size's 8 x 8 page would be too
//! big to leave mostly empty (a 512 one is a whole layer), and its block is already tight, so 256 pixels and up are
//! buddy blocks of their own.
//!
//! Layers are added and taken off the end by the texture manager (AddLayer, RemoveLayers), which grows and shrinks the
//! GPU texture to match. CPU only, no GPU needed.
const std = @import("std");
const AtlasHandle = @import("AtlasHandle.zig");

const AtlasSlots = @This();

/// The buddy's block levels: a whole layer (0, 4096 pixels) down to its smallest block (4, 256 pixels)
pub const LEVELS = 5;
/// Classes below this (64 and 128 pixels) are binned in pages; the rest are buddy blocks of their own
pub const BINNED_CLASSES = 2;
const BLOCK_CLASSES = AtlasHandle.CLASS_COUNT - BINNED_CLASSES;
/// Every node of a layer's tree: the layer, its 4 quarters, their 16, then 64, then 256
const NODE_COUNT = 1 + 4 + 16 + 64 + 256;
const LEVEL_START = [LEVELS]usize{ 0, 1, 5, 21, 85 };
/// A page is always this many slots across, and down
pub const PAGE_SLOTS_PER_ROW = 8;
const PAGE_SLOTS = PAGE_SLOTS_PER_ROW * PAGE_SLOTS_PER_ROW;

const NodeState = enum(u8) {
    /// a free block, or part of one above it
    Free,
    /// split into its four quarters
    Split,
    /// a block given out
    Used,
};

/// One layer's tree of blocks
const Layer = struct {
    mNodes: [NODE_COUNT]NodeState = @splat(.Free),
};

/// A block where in a layer
const Block = struct {
    Layer: u32,
    Level: usize,
    /// in blocks of its level from the layer's top left
    X: u32,
    Y: u32,
};

/// A bin's page: a block 8 x 8 of the bin's slots, a bit for each, set while it holds a texture. Where it is, in blocks of
/// its level (PageLevel)
const Page = struct {
    mLayer: u32,
    mX: u32,
    mY: u32,
    mSlots: std.StaticBitSet(PAGE_SLOTS) = .empty,
    mUsed: u32 = 0,
};

/// How much one size class takes
pub const ClassUsage = struct {
    /// the biggest texture its slots take, either way
    MaxSize: u32,
    /// slots holding a texture
    Used: u32,
    /// slots its pages have, Used for a class that has no pages
    Capacity: u32,
    /// how many bytes one of its slots is, padding included
    SlotBytes: usize,
    /// pages of 8 x 8 slots it has taken from the buddy, 0 for a class that takes blocks of its own
    Pages: u32,
};

mLayers: std.ArrayList(Layer) = .empty,
mPages: [BINNED_CLASSES]std.ArrayList(Page) = @splat(.empty),
/// how many blocks each unbinned class holds
mBlocks: [BLOCK_CLASSES]u32 = @splat(0),

pub fn Deinit(self: *AtlasSlots, keep_allocator: std.mem.Allocator) void {
    self.mLayers.deinit(keep_allocator);
    for (&self.mPages) |*pages| pages.deinit(keep_allocator);
}

pub fn LayerCount(self: AtlasSlots) usize {
    return self.mLayers.items.len;
}

/// A free layer on the end
pub fn AddLayer(self: *AtlasSlots, keep_allocator: std.mem.Allocator) !void {
    std.debug.assert(self.mLayers.items.len < AtlasHandle.MAX_LAYERS);
    try self.mLayers.append(keep_allocator, .{});
}

/// How many layers at the end hold nothing
pub fn TrailingFreeLayers(self: AtlasSlots) usize {
    var count: usize = 0;
    var layer_ind = self.mLayers.items.len;
    while (layer_ind > 0) : (layer_ind -= 1) {
        if (self.mLayers.items[layer_ind - 1].mNodes[0] != .Free) break;
        count += 1;
    }
    return count;
}

/// Takes `count` free layers off the end
pub fn RemoveLayers(self: *AtlasSlots, count: usize) void {
    std.debug.assert(count <= self.TrailingFreeLayers());
    self.mLayers.shrinkRetainingCapacity(self.mLayers.items.len - count);
}

/// A slot for a texture of `class` (AtlasHandle.ClassOf), as a handle. Null when every layer is full for it: the texture
/// manager adds a layer and asks again
pub fn Alloc(self: *AtlasSlots, keep_allocator: std.mem.Allocator, class: u32) !?u32 {
    if (class >= BINNED_CLASSES) {
        const level = LevelOf(class);
        const block = self.TakeBlock(level) orelse return null;
        self.mBlocks[class - BINNED_CLASSES] += 1;
        return AtlasHandle.Make(block.Layer, block.X * BlockCells(level), block.Y * BlockCells(level), class);
    }

    const pages = &self.mPages[class];
    const page = for (pages.items) |*page| {
        if (page.mUsed < PAGE_SLOTS) break page;
    } else new: {
        const block = self.TakeBlock(PageLevel(class)) orelse return null;
        try pages.append(keep_allocator, .{ .mLayer = block.Layer, .mX = block.X, .mY = block.Y });
        break :new &pages.items[pages.items.len - 1];
    };

    const free = page.mSlots.complement();
    const slot: u32 = @intCast(free.findFirstSet().?);
    page.mSlots.set(slot);
    page.mUsed += 1;

    const page_cells = BlockCells(PageLevel(class));
    const slot_cells = AtlasHandle.SlotSize(class) / AtlasHandle.CELL;
    return AtlasHandle.Make(
        page.mLayer,
        page.mX * page_cells + (slot % PAGE_SLOTS_PER_ROW) * slot_cells,
        page.mY * page_cells + (slot / PAGE_SLOTS_PER_ROW) * slot_cells,
        class,
    );
}

/// Gives back the slot `handle` was given
pub fn Free(self: *AtlasSlots, handle: u32) void {
    const class = AtlasHandle.Class(handle);
    const layer = AtlasHandle.Layer(handle);
    const cell_x = AtlasHandle.CellX(handle);
    const cell_y = AtlasHandle.CellY(handle);

    if (class >= BINNED_CLASSES) {
        const level = LevelOf(class);
        self.GiveBlock(.{ .Layer = layer, .Level = level, .X = cell_x / BlockCells(level), .Y = cell_y / BlockCells(level) });
        self.mBlocks[class - BINNED_CLASSES] -= 1;
        return;
    }

    const page_level = PageLevel(class);
    const page_cells = BlockCells(page_level);
    const page_x = cell_x / page_cells;
    const page_y = cell_y / page_cells;
    const pages = &self.mPages[class];
    for (pages.items, 0..) |*page, page_ind| {
        if (page.mLayer != layer or page.mX != page_x or page.mY != page_y) continue;
        const slot_cells = AtlasHandle.SlotSize(class) / AtlasHandle.CELL;
        const slot = ((cell_y % page_cells) / slot_cells) * PAGE_SLOTS_PER_ROW + (cell_x % page_cells) / slot_cells;
        std.debug.assert(page.mSlots.isSet(slot));
        page.mSlots.unset(slot);
        page.mUsed -= 1;
        if (page.mUsed == 0) {
            self.GiveBlock(.{ .Layer = page.mLayer, .Level = page_level, .X = page.mX, .Y = page.mY });
            _ = pages.swapRemove(page_ind);
        }
        return;
    }
    unreachable;
}

/// How much each size class takes, smallest first
pub fn Usage(self: AtlasSlots) [AtlasHandle.CLASS_COUNT]ClassUsage {
    var usage: [AtlasHandle.CLASS_COUNT]ClassUsage = undefined;
    for (&usage, 0..) |*class_usage, class_ind| {
        const class: u32 = @intCast(class_ind);
        const slot_size: usize = AtlasHandle.SlotSize(class);
        class_usage.* = .{ .MaxSize = AtlasHandle.MaxTextureSize(class), .Used = 0, .Capacity = 0, .SlotBytes = slot_size * slot_size * 4, .Pages = 0 };
        if (class < BINNED_CLASSES) {
            for (self.mPages[class].items) |page| class_usage.Used += page.mUsed;
            class_usage.Pages = @intCast(self.mPages[class].items.len);
            class_usage.Capacity = class_usage.Pages * PAGE_SLOTS;
        } else {
            class_usage.Used = self.mBlocks[class - BINNED_CLASSES];
            class_usage.Capacity = class_usage.Used;
        }
    }
    return usage;
}

/// The smallest free block at least as big as `level`'s, in the lowest layer, split down to `level` and taken. Null if
/// there is none
fn TakeBlock(self: *AtlasSlots, level: usize) ?Block {
    var from = level + 1;
    while (from > 0) {
        from -= 1;
        for (self.mLayers.items, 0..) |*layer, layer_ind| {
            const grid = Grid(from);
            for (0..grid * grid) |position| {
                const x: u32 = @intCast(position % grid);
                const y: u32 = @intCast(position / grid);
                if (layer.mNodes[NodeIndex(from, x, y)] != .Free or !IsBlock(layer, from, x, y)) continue;
                return SplitDown(layer, .{ .Layer = @intCast(layer_ind), .Level = from, .X = x, .Y = y }, level);
            }
        }
    }
    return null;
}

/// Splits the free block `block` until its top left quarter is `level`'s size, and takes that
fn SplitDown(layer: *Layer, block: Block, level: usize) Block {
    var current = block;
    while (current.Level < level) {
        layer.mNodes[NodeIndex(current.Level, current.X, current.Y)] = .Split;
        current = .{ .Layer = current.Layer, .Level = current.Level + 1, .X = current.X * 2, .Y = current.Y * 2 };
    }
    layer.mNodes[NodeIndex(current.Level, current.X, current.Y)] = .Used;
    return current;
}

/// Frees `block`, merging it into the block above for as long as all four quarters of that are free
fn GiveBlock(self: *AtlasSlots, block: Block) void {
    const layer = &self.mLayers.items[block.Layer];
    std.debug.assert(layer.mNodes[NodeIndex(block.Level, block.X, block.Y)] == .Used);
    layer.mNodes[NodeIndex(block.Level, block.X, block.Y)] = .Free;
    var level = block.Level;
    var x = block.X;
    var y = block.Y;
    while (level > 0) {
        const parent_x = x / 2;
        const parent_y = y / 2;
        for (0..4) |quarter| {
            if (layer.mNodes[NodeIndex(level, parent_x * 2 + @as(u32, @intCast(quarter % 2)), parent_y * 2 + @as(u32, @intCast(quarter / 2)))] != .Free) return;
        }
        level -= 1;
        x = parent_x;
        y = parent_y;
        layer.mNodes[NodeIndex(level, x, y)] = .Free;
    }
}

/// Whether a node is a block of its own: the layer, or a quarter of a block that was split. A free node inside a bigger
/// free block is part of that block
fn IsBlock(layer: *const Layer, level: usize, x: u32, y: u32) bool {
    if (level == 0) return true;
    return layer.mNodes[NodeIndex(level - 1, x / 2, y / 2)] == .Split;
}

/// The level of a block a class's slot is: 4096 a layer, 2048 a quarter, and so on down to 256
fn LevelOf(class: u32) usize {
    return AtlasHandle.CLASS_COUNT - 1 - class;
}

/// The level of a binned class's page: a block 8 slots across, three classes up
fn PageLevel(class: u32) usize {
    return LevelOf(class + 3);
}

/// Blocks across a layer at `level`
fn Grid(level: usize) u32 {
    return @as(u32, 1) << @intCast(level);
}

/// Cells across a block of `level`
fn BlockCells(level: usize) u32 {
    return AtlasHandle.CELLS >> @intCast(level);
}

fn NodeIndex(level: usize, x: u32, y: u32) usize {
    return LEVEL_START[level] + y * Grid(level) + x;
}

