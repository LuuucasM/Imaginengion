//! Bounding volume hierarchy: a tree of boxes over a set of items, so a ray or a box only has to be tested against
//! the few items whose boxes it reaches. Generic over plain boxes (Aabb), knowing nothing about what the items are: the
//! renderer builds one over its shapes, and the same code can build one over colliders.
//!
//! Built in stages, each its own piece:
//! - the binary build: top down, each node's items split in two where the surface area heuristic says a ray will
//!   pay least for them (binned, see Split), the items reordered as it goes so each leaf's are a run of them
//! - layouts: how the tree is laid out for whoever walks it. Node holds both ways to walk it: each inner node's two
//!   children, which the GPU walks into the nearer one first (SDFRayMarcher.NearestByBVH, depth kept to MAX_DEPTH),
//!   and Skip links for a walk with no stack in a fixed order, the CPU's (WalkRay). Wider trees (4 or 8 children) would
//!   be another layout, collapsed from the binary one
const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Aabb = @import("../Math/Aabb.zig");
const RayIntersect = @import("../Math/RayIntersect.zig");
const Ray = @import("../Math/CameraRay.zig").Ray;
const GPUAsserts = @import("GPUAsserts.zig");
const Tracy = @import("Tracy.zig");

//==================================the tree==================================

/// Which systems an item is for, so one tree can be shared and each walk passes over what is not its own. A node's
/// mask is the masks of everything under it ORed together, so a walk skips a whole branch of the other system's
/// items in one test. 4 bits, kept in Node.Info
pub const Mask = struct {
    pub const RENDER: u4 = 1 << 0;
    pub const PHYSICS: u4 = 1 << 1;
    /// what a click can land on: what is drawn, and see-through quads that draw nothing but still take clicks (row buttons)
    pub const PICK: u4 = 1 << 2;
};

/// The most items a leaf holds. Fewer means a deeper tree, more boxes tested on the way down and fewer items tested
/// at the bottom; more means the other way round. A cap: a leaf can hold anything from 1 up to it
pub const MAX_LEAF_ITEMS: u32 = 4;

//Node.Info: the first item (or, for an inner node, its right child) in the top 24 bits, the mask in the next 4, the
//item count in the low 4. A count of 0 is an inner node
const INFO_COUNT_BITS = 4;
const INFO_MASK_BITS = 4;
const INFO_INDEX_SHIFT = INFO_COUNT_BITS + INFO_MASK_BITS;
const INFO_COUNT_FIELD: u32 = (1 << INFO_COUNT_BITS) - 1;
const INFO_MASK_FIELD: u32 = (1 << INFO_MASK_BITS) - 1;
/// The most items a tree can hold, from the 24 bits of Info an index gets
pub const MAX_ITEMS: u32 = 1 << (32 - INFO_INDEX_SHIFT);

comptime {
    std.debug.assert(MAX_LEAF_ITEMS <= INFO_COUNT_FIELD);
}

/// One node of the tree, laid out the same for the CPU and the GPU: 32 bytes, plain floats rather than vectors so
/// there is no padding. Nodes are stored depth first: a node's first child is the node right after it, and its
/// whole subtree follows it in one run, which is what lets a walk go without a stack (see Skip)
pub const Node = extern struct {
    MinX: f32,
    MinY: f32,
    MinZ: f32,
    /// The node right after this one's whole subtree: where a walk goes once it has missed this node's box or
    /// finished with it. The root's is the node count, the end of the walk. The CPU's stack free walks (WalkRay,
    /// WalkBox) use them; the GPU goes into the nearer child first instead
    Skip: u32,
    MaxX: f32,
    MaxY: f32,
    MaxZ: f32,
    /// For a leaf: its first item and how many it has (its items are that run of the sorted items). For an inner
    /// node: a count of 0, and its right child where a leaf has its first item (its left child is the next node).
    /// The mask of everything under it either way. Read through the functions below
    Info: u32,

    pub fn ItemCount(self: Node) u32 {
        return self.Info & INFO_COUNT_FIELD;
    }
    pub fn IsLeaf(self: Node) bool {
        return self.ItemCount() != 0;
    }
    /// A leaf's first item
    pub fn FirstItem(self: Node) u32 {
        return self.Info >> INFO_INDEX_SHIFT;
    }
    /// An inner node's right child
    pub fn RightChild(self: Node) u32 {
        return self.Info >> INFO_INDEX_SHIFT;
    }
    pub fn ItemMask(self: Node) u32 {
        return (self.Info >> INFO_COUNT_BITS) & INFO_MASK_FIELD;
    }
    pub fn Bounds(self: Node) Aabb {
        return .{ .Min = .{ .x = self.MinX, .y = self.MinY, .z = self.MinZ }, .Max = .{ .x = self.MaxX, .y = self.MaxY, .z = self.MaxZ } };
    }

    fn Init(index: u32, count: u32) Node {
        return .{ .MinX = 0, .MinY = 0, .MinZ = 0, .Skip = 0, .MaxX = 0, .MaxY = 0, .MaxZ = 0, .Info = (index << INFO_INDEX_SHIFT) | count };
    }
    fn SetIndex(self: *Node, index: u32) void {
        self.Info = (self.Info & ((1 << INFO_INDEX_SHIFT) - 1)) | (index << INFO_INDEX_SHIFT);
    }
    fn SetMask(self: *Node, mask: u32) void {
        self.Info = (self.Info & ~(INFO_MASK_FIELD << INFO_COUNT_BITS)) | ((mask & INFO_MASK_FIELD) << INFO_COUNT_BITS);
    }
    fn SetBounds(self: *Node, bounds: Aabb) void {
        self.MinX = bounds.Min.x;
        self.MinY = bounds.Min.y;
        self.MinZ = bounds.Min.z;
        self.MaxX = bounds.Max.x;
        self.MaxY = bounds.Max.y;
        self.MaxZ = bounds.Max.z;
    }
};

comptime {
    std.debug.assert(@sizeOf(Node) == 32);
    GPUAsserts.AssertGPULayout(Node);
}

//// One item a tree is built over: its box, its mask, and an Id for whatever it stands for. A build reorders the items
/// so each leaf's are a run of them, found by its FirstItem and ItemCount, and whoever built it puts what the items
/// stand for in that same order by their Ids
pub const Item = struct {
    /// the builder's own: the shape, collider... the item is, which the build carries along and never reads
    Id: u32,
    Bounds: Aabb,
    Mask: u4,
};

/// The deepest a leaf can be, the root being 0. A walk that goes into the nearer child first keeps the farther one to
/// come back to, at most one per level, so this is how many it can be holding (SDFRayMarcher.NearestByBVH). Build
/// keeps to it by splitting down the middle wherever its chosen split would leave a half too big to fit
pub const MAX_DEPTH: u32 = 32;

/// How many levels a range of `count` items needs below it at the least, split down the middle each time
fn LevelsBelow(count: u32) u32 {
    var levels: u32 = 0;
    var left = count;
    while (left > MAX_LEAF_ITEMS) : (levels += 1) left = left - left / 2;
    return levels;
}

comptime {
    //even the most items fit under MAX_DEPTH split down the middle, so a build can always keep to it
    std.debug.assert(LevelsBelow(MAX_ITEMS) <= MAX_DEPTH);
}

/// How many ranges the build can have waiting: only right halves wait their turn, at most one per level
const MAX_BUILD_DEPTH = MAX_DEPTH + 1;

/// The tree over `items` into `nodes` (cleared first, its memory kept), reordering `items` so each leaf's are a run of
/// them. The same items in the same order always build the same tree. No recursion: one pass makes the nodes depth
/// first from a list of ranges still to do, splitting each range's items as it gets to it, one pass forward fills in
/// each node's Skip, and Refit fills in the boxes and masks going back up
pub fn Build(allocator: std.mem.Allocator, items: []Item, nodes: *std.ArrayList(Node)) !void {
    const zone = Tracy.ZoneInit("BVH::Build", @src());
    defer zone.Deinit();
    zone.Value(items.len);

    nodes.clearRetainingCapacity();
    if (items.len == 0) return;
    std.debug.assert(items.len <= MAX_ITEMS);

    try BuildStructure(allocator, items, nodes);
    FillSkips(nodes.items);
    Refit(items, nodes.items);
}

/// Build's nodes, depth first, each range's items split as it gets to it. Every node's box and mask left for Refit
fn BuildStructure(allocator: std.mem.Allocator, items: []Item, nodes: *std.ArrayList(Node)) !void {
    const zone = Tracy.ZoneInit("BVH::BuildStructure", @src());
    defer zone.Deinit();

    //the structure, depth first. A range waiting its turn is a right half, whose parent's Info gets its index once it
    //is made, or the root. Each carries the box around its items' centers, found by the split that made it
    const Pending = struct { First: u32, End: u32, RightOf: ?u32, Depth: u32, Centers: CenterBox };
    var pending: [MAX_BUILD_DEPTH]Pending = undefined;
    var pending_count: usize = 1;
    pending[0] = .{ .First = 0, .End = @intCast(items.len), .RightOf = null, .Depth = 0, .Centers = .Of(items) };

    while (pending_count > 0) {
        pending_count -= 1;
        const range = pending[pending_count];
        const node_ind: u32 = @intCast(nodes.items.len);
        if (range.RightOf) |parent| nodes.items[parent].SetIndex(node_ind);

        const count = range.End - range.First;
        if (count <= MAX_LEAF_ITEMS) {
            try nodes.append(allocator, Node.Init(range.First, count));
            continue;
        }

        //an inner node: its right half waits, its left half is made next, so it lands right after it
        try nodes.append(allocator, Node.Init(0, 0));
        const halves = Split(items[range.First..range.End], range.Depth, range.Centers);
        const split = range.First + halves.LeftCount;
        std.debug.assert(pending_count + 2 <= MAX_BUILD_DEPTH);
        pending[pending_count] = .{ .First = split, .End = range.End, .RightOf = node_ind, .Depth = range.Depth + 1, .Centers = halves.Right };
        pending[pending_count + 1] = .{ .First = range.First, .End = split, .RightOf = null, .Depth = range.Depth + 1, .Centers = halves.Left };
        pending_count += 2;
    }
    zone.Value(nodes.items.len);
}

/// Where each node's walk goes next. A parent comes before its children, so its own Skip is always set by the time
/// its children's are worked out from it
fn FillSkips(nodes: []Node) void {
    const zone = Tracy.ZoneInit("BVH::FillSkips", @src());
    defer zone.Deinit();

    nodes[0].Skip = @intCast(nodes.len);
    for (nodes, 0..) |node, node_ind| {
        if (node.IsLeaf()) continue;
        const left = node_ind + 1;
        const right = node.RightChild();
        nodes[left].Skip = right;
        nodes[right].Skip = node.Skip;
    }
}

//// How many bins a split sorts a node's items into along each axis, by where their centers are, to try a split at
/// every boundary between two: more finds a slightly better split, fewer builds slightly faster
pub const SAH_BINS: u32 = 16;

/// x, y and z at once
const Vec3V = @Vector(3, f32);

/// Where the build places an item: twice its center, its box's Min + Max, which saves halving it. Every center in a
/// split is doubled the same way, so which bin each lands in is exactly as if they weren't
fn DoubledCenter(item: Item) Vec3V {
    return item.Bounds.Min.ToVector() + item.Bounds.Max.ToVector();
}

/// Which bin along each axis a doubled center falls in, the bins starting at `min` and `scale` of them a unit along
/// each. An axis with a scale of 0 puts everything in bin 0
fn BinsOf(doubled_center: Vec3V, min: Vec3V, scale: Vec3V) @Vector(3, u32) {
    const bins: @Vector(3, u32) = @intFromFloat((doubled_center - min) * scale);
    return @min(bins, @as(@Vector(3, u32), @splat(SAH_BINS - 1)));
}

/// A split BestSplit has picked: the items whose centers fall in bins below Bin along Axis go left. Min and Scale
/// place a center in its bins (BinsOf), kept so the items are put in exactly the bins they were counted in
const SplitChoice = struct {
    Axis: usize,
    Bin: u32,
    LeftCount: u32,
    Min: Vec3V,
    Scale: Vec3V,
};

/// The box around some items' doubled centers: what a split places them in its bins by
const CenterBox = struct {
    Min: Vec3V = @splat(std.math.inf(f32)),
    Max: Vec3V = @splat(-std.math.inf(f32)),

    fn Of(items: []const Item) CenterBox {
        var box = CenterBox{};
        for (items) |item| box.Add(DoubledCenter(item));
        return box;
    }
    fn Add(self: *CenterBox, center: Vec3V) void {
        self.Min = @min(self.Min, center);
        self.Max = @max(self.Max, center);
    }
};

/// How a split left a range: how many items went left, and the box around each half's centers, which is what each
/// half is split by in turn
const Halves = struct {
    LeftCount: u32,
    Left: CenterBox,
    Right: CenterBox,
};

/// Splits `items`, more than a leaf holds and whose centers are in `centers`, in two at depth `depth`: reorders them
/// so the left half comes first. The split is the cheapest by the surface area heuristic (BestSplit). Items whose
/// centers are all in one spot, which no plane splits, and a split leaving a half too big to fit in the levels left
/// under MAX_DEPTH, the way items each much further out than the last would peel off one at a time, go down the middle
/// instead, which always fits
fn Split(items: []Item, depth: u32, centers: CenterBox) Halves {
    const count: u32 = @intCast(items.len);
    if (BestSplit(items, centers)) |best| {
        const bigger_half = @max(best.LeftCount, count - best.LeftCount);
        if (depth + 1 + LevelsBelow(bigger_half) <= MAX_DEPTH) return Partition(items, best);
    }
    SortAlongWidest(items, centers.Max - centers.Min);
    const half = count / 2;
    return .{ .LeftCount = half, .Left = .Of(items[0..half]), .Right = .Of(items[half..]) };
}

/// A box as one vector, so one @min is the union of two: its Min in the first three lanes, its Max negated in the
/// next three, and inf in the two left over. All inf is the empty box
const BoxV = @Vector(8, f32);
const EMPTY_BOX_V: BoxV = @splat(std.math.inf(f32));

fn BoxVOf(bounds: Aabb) BoxV {
    const inf = std.math.inf(f32);
    return .{ bounds.Min.x, bounds.Min.y, bounds.Min.z, inf, -bounds.Max.x, -bounds.Max.y, -bounds.Max.z, inf };
}

/// What the surface area heuristic charges for `count` items in `box`: its half area (Aabb.HalfArea) times the count
fn BoxVCost(box: BoxV, count: u32) f32 {
    const size_x = -box[4] - box[0];
    const size_y = -box[5] - box[1];
    const size_z = -box[6] - box[2];
    return (size_x * size_y + size_y * size_z + size_z * size_x) * @as(f32, @floatFromInt(count));
}

/// The cheapest split of `items`, whose doubled centers are in `centers`, or null if every center is in one spot. Along
/// each axis the centers spread over, the items go into SAH_BINS bins, each keeping a box around its items and how many
/// there are, all three axes' bins filled in one pass over the items. Each boundary between two bins is a split: its
/// cost is each side's box's surface area times how many items it holds, added up. A ray through the node goes through
/// a box with a chance in proportion to its area, and then has its items to pay for, so the cheapest split is the one a
/// ray pays least for
fn BestSplit(items: []const Item, centers: CenterBox) ?SplitChoice {
    const extent = centers.Max - centers.Min;
    const zero: Vec3V = @splat(0);
    if (!@reduce(.Or, extent > zero)) return null;
    //a flat axis gets a scale of 0, and is passed over below
    const scale = @select(f32, extent > zero, @as(Vec3V, @splat(@floatFromInt(SAH_BINS))) / extent, zero);

    var boxes: [3][SAH_BINS]BoxV = @splat(@splat(EMPTY_BOX_V));
    var counts: [3][SAH_BINS]u32 = @splat(@splat(0));
    for (items) |item| {
        const item_bins = BinsOf(DoubledCenter(item), centers.Min, scale);
        const item_box = BoxVOf(item.Bounds);
        inline for (0..3) |axis| {
            const bin = item_bins[axis];
            boxes[axis][bin] = @min(boxes[axis][bin], item_box);
            counts[axis][bin] += 1;
        }
    }

    var best: ?SplitChoice = null;
    var best_cost = std.math.inf(f32);
    const extents: [3]f32 = extent;
    for (0..3) |axis| {
        if (!(extents[axis] > 0)) continue;
        const axis_boxes = &boxes[axis];
        const axis_counts = &counts[axis];

        //the bins with items in, in order. A boundary just past an empty bin splits the items exactly as the one before
        //it did, at the same cost, so only the boundary between each of these and the next is tried
        var filled: [SAH_BINS]u32 = undefined;
        var filled_count: usize = 0;
        const counts_v: @Vector(SAH_BINS, u32) = axis_counts.*;
        var occupied: u32 = @as(@Int(.unsigned, SAH_BINS), @bitCast(counts_v != @as(@Vector(SAH_BINS, u32), @splat(0))));
        while (occupied != 0) : (occupied &= occupied - 1) {
            filled[filled_count] = @ctz(occupied);
            filled_count += 1;
        }

        //every boundary's right side, swept in from the right end: what is in the filled bin just past it and every
        //one after that
        var right_costs: [SAH_BINS]f32 = undefined;
        var right_box = EMPTY_BOX_V;
        var right_count: u32 = 0;
        var filled_ind = filled_count;
        while (filled_ind > 1) {
            filled_ind -= 1;
            const bin = filled[filled_ind];
            right_box = @min(right_box, axis_boxes[bin]);
            right_count += axis_counts[bin];
            right_costs[filled_ind] = BoxVCost(right_box, right_count);
        }

        //then each boundary's left side, swept in from the left end. The first cheapest wins a tie, so the same items
        //always split the same way
        var left_box = EMPTY_BOX_V;
        var left_count: u32 = 0;
        for (filled[0 .. filled_count -| 1], 0..) |bin, left_ind| {
            left_box = @min(left_box, axis_boxes[bin]);
            left_count += axis_counts[bin];
            const cost = BoxVCost(left_box, left_count) + right_costs[left_ind + 1];
            if (cost < best_cost) {
                best_cost = cost;
                best = .{ .Axis = axis, .Bin = bin + 1, .LeftCount = left_count, .Min = centers.Min, .Scale = scale };
            }
        }
    }
    return best;
}

/// Reorders `items` so the ones `split` puts on the left come first, finding each half's center box on the way
fn Partition(items: []Item, split: SplitChoice) Halves {
    var halves = Halves{ .LeftCount = split.LeftCount, .Left = .{}, .Right = .{} };
    var left: usize = 0;
    var right = items.len;
    while (left < right) {
        const center = DoubledCenter(items[left]);
        const item_bins: [3]u32 = BinsOf(center, split.Min, split.Scale);
        if (item_bins[split.Axis] < split.Bin) {
            halves.Left.Add(center);
            left += 1;
        } else {
            halves.Right.Add(center);
            right -= 1;
            std.mem.swap(Item, &items[left], &items[right]);
        }
    }
    std.debug.assert(left == split.LeftCount);
    return halves;
}

/// Sorts `items` by their centers along the axis their centers spread widest on (`extent`), so splitting them down the
/// middle still splits them in space. Items whose centers are all in one spot stay as they are
fn SortAlongWidest(items: []Item, extent_v: Vec3V) void {
    const extent: [3]f32 = extent_v;
    var axis: usize = 0;
    for (1..3) |other| {
        if (extent[other] > extent[axis]) axis = other;
    }
    if (!(extent[axis] > 0)) return;
    std.sort.pdq(Item, items, axis, struct {
        fn lessThan(on: usize, a: Item, b: Item) bool {
            const a_center: [3]f32 = DoubledCenter(a);
            const b_center: [3]f32 = DoubledCenter(b);
            return a_center[on] < b_center[on];
        }
    }.lessThan);
}

/// Each node's box and mask from the items under it, going back up: every node after its children, which come
/// after it. What a build finishes with, and all a tree needs after its items move, as long as it still holds the
/// same items in the same order. Boxes moving far from where they were built make a looser tree, which a rebuild fixes
pub fn Refit(items: []const Item, nodes: []Node) void {
    const zone = Tracy.ZoneInit("BVH::Refit", @src());
    defer zone.Deinit();

    var node_ind = nodes.len;
    while (node_ind > 0) {
        node_ind -= 1;
        const node = &nodes[node_ind];
        var bounds = Aabb.empty;
        var mask: u32 = 0;
        if (node.IsLeaf()) {
            for (items[node.FirstItem()..][0..node.ItemCount()]) |item| {
                bounds = bounds.Union(item.Bounds);
                mask |= item.Mask;
            }
        } else {
            const left = nodes[node_ind + 1];
            const right = nodes[node.RightChild()];
            bounds = left.Bounds().Union(right.Bounds());
            mask = left.ItemMask() | right.ItemMask();
        }
        node.SetBounds(bounds);
        node.SetMask(mask);
    }
}

/// What a built tree looks like, for the editor's stats: how much a walk has to go through. The deeper its leaves, the
/// more boxes every ray tests on its way down
pub const TreeStats = struct {
    Nodes: u32 = 0,
    Leaves: u32 = 0,
    /// how deep its deepest leaf is, the root being 0 (never more than MAX_DEPTH)
    Depth: u32 = 0,
    /// every leaf's depth added up, for the average
    LeafDepths: u32 = 0,
    Items: u32 = 0,
    /// How many boxes and items a ray through the root tests on average, if it went into every box it goes through and
    /// stopped at none: the root's box, each inner node's two children's and each leaf's items, each counted by the
    /// chance a ray through the root goes through that node's box, its surface area over the root's. What the build
    /// keeps low (BestSplit): lower is a better tree for the same items
    Cost: f32 = 0,

    /// How deep a leaf is on average: about how many levels a ray goes down to reach one
    pub fn AverageLeafDepth(self: TreeStats) f32 {
        if (self.Leaves == 0) return 0;
        return @as(f32, @floatFromInt(self.LeafDepths)) / @as(f32, @floatFromInt(self.Leaves));
    }

    /// How many items a leaf holds on average, out of MAX_LEAF_ITEMS
    pub fn AverageLeafItems(self: TreeStats) f32 {
        if (self.Leaves == 0) return 0;
        return @as(f32, @floatFromInt(self.Items)) / @as(f32, @floatFromInt(self.Leaves));
    }

    /// The bigger of two trees' stats, by node count: what a render keeps when it builds a tree for each view
    pub fn Bigger(self: TreeStats, other: TreeStats) TreeStats {
        return if (other.Nodes > self.Nodes) other else self;
    }
};

/// The stats of the tree in `nodes`, found by going down every branch
pub fn Stats(nodes: []const Node) TreeStats {
    var stats = TreeStats{ .Nodes = @intCast(nodes.len) };
    if (nodes.len == 0) return stats;
    //a root with no area, everything in one point, has every ray through it go through everything
    const root_area = nodes[0].Bounds().HalfArea();
    stats.Cost = 1;

    //the branches still to go down, each with its depth. Going down one keeps the other, at most one per level
    const Branch = struct { Node: u32, Depth: u32 };
    var waiting: [MAX_DEPTH + 1]Branch = undefined;
    var waiting_count: usize = 1;
    waiting[0] = .{ .Node = 0, .Depth = 0 };
    while (waiting_count > 0) {
        waiting_count -= 1;
        const branch = waiting[waiting_count];
        const node = nodes[branch.Node];
        const chance = if (root_area > 0) node.Bounds().HalfArea() / root_area else 1;
        if (node.IsLeaf()) {
            stats.Cost += chance * @as(f32, @floatFromInt(node.ItemCount()));
            stats.Leaves += 1;
            stats.Items += node.ItemCount();
            stats.LeafDepths += branch.Depth;
            stats.Depth = @max(stats.Depth, branch.Depth);
            continue;
        }
        stats.Cost += chance * 2;
        waiting[waiting_count] = .{ .Node = node.RightChild(), .Depth = branch.Depth + 1 };
        waiting[waiting_count + 1] = .{ .Node = branch.Node + 1, .Depth = branch.Depth + 1 };
        waiting_count += 2;
    }
    return stats;
}

/// Walks the tree with a box, the stack free way, in the tree's own fixed order: into each node whose box overlaps `box`
/// and that has any of `mask`, and on to its Skip past any that doesn't. Every item of each leaf it reaches is handed to
/// `visitor.Visit(item_index)`. A leaf's items can have different boxes and masks, so the visitor checks an item's own
/// if that matters
pub fn WalkBox(nodes: []const Node, box: Aabb, mask: u32, visitor: anytype) !void {
    var node_ind: u32 = 0;
    while (node_ind < nodes.len) {
        const node = nodes[node_ind];
        if (node.ItemMask() & mask == 0 or !node.Bounds().Overlaps(box)) {
            node_ind = node.Skip;
            continue;
        }
        if (!node.IsLeaf()) {
            node_ind += 1;
            continue;
        }
        for (node.FirstItem()..node.FirstItem() + node.ItemCount()) |item_ind| {
            try visitor.Visit(@intCast(item_ind));
        }
        node_ind = node.Skip;
    }
}

/// Walks the tree with a ray, the stack free way, in the tree's own fixed order: into each node whose box the ray
/// reaches within how far is still worth looking and that has any of `mask`, and on to its Skip past any that it does
/// not. Every item of each leaf it reaches is handed to `visitor.Visit(item_index)`, which returns how far along the ray
/// is still worth looking: the nearest hit so far for a nearest hit search, which then passes over every box starting
/// past it, or `max_t` again to see them all. A leaf's items can have different masks, so the visitor checks an item's
/// own if that matters
pub fn WalkRay(nodes: []const Node, ray: Ray, max_t: f32, mask: u32, visitor: anytype) void {
    WalkSweep(nodes, ray, 0, max_t, mask, visitor) catch unreachable;
}

/// WalkRay for a shape moving along the ray, as far as `radius` out from it every way (a sphere's radius, a box's
/// half diagonal): every box is grown by it as it is tested, so the shape can't slip past a box its centre misses.
/// The visitor's Visit can fail, and the walk stops with its error
pub fn WalkSweep(nodes: []const Node, ray: Ray, radius: f32, max_t: f32, mask: u32, visitor: anytype) !void {
    const inv_dir = Vec3(f32).FromVector(@as(Vec3(f32).VectorT, @splat(1.0)) / ray.Dir.ToVector());
    var reach = max_t;
    var node_ind: u32 = 0;
    while (node_ind < nodes.len) {
        const node = nodes[node_ind];
        const bounds = node.Bounds().Grow(radius);
        const span = RayIntersect.RayAabb(ray.Origin, inv_dir, bounds.Min, bounds.Max);
        const reached = if (span) |s| s.Enter <= reach and node.ItemMask() & mask != 0 else false;
        if (!reached) {
            node_ind = node.Skip;
            continue;
        }
        if (!node.IsLeaf()) {
            node_ind += 1;
            continue;
        }
        for (node.FirstItem()..node.FirstItem() + node.ItemCount()) |item_ind| {
            const visited = visitor.Visit(@intCast(item_ind));
            const item_reach = if (@typeInfo(@TypeOf(visited)) == .error_union) try visited else visited;
            reach = @min(reach, item_reach);
        }
        node_ind = node.Skip;
    }
}
