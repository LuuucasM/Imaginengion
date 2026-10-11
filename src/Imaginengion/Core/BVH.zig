//! Bounding volume hierarchy: a tree of boxes over a set of items, so a ray or a box only has to be tested against
//! the few items whose boxes it reaches. Generic over plain boxes (Aabb), knowing nothing about what the items are: the
//! renderer builds one over its shapes, and the same code can build one over colliders.
//!
//! Built in stages, each its own piece:
//! - Morton ordering: a number per item from where its center is, which sorting by puts items close in space next
//!   to each other
//! - the binary build: split the sorted items where their Morton codes first differ, down to small leaves
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

//==================================Morton ordering==================================

/// How finely each axis is cut: 2^10 = 1024 steps each, 30 bits in all, which fits a u32 with room to spare
pub const MORTON_BITS_PER_AXIS = 10;
const MORTON_STEPS: f32 = 1 << MORTON_BITS_PER_AXIS;

/// Spreads the low 10 bits of `value` out with two zero bits between each, so three of them can be interleaved
/// into one number: bit i lands at bit 3i
pub fn SpreadBits(value: u32) u32 {
    var v = value & 0x3FF;
    v = (v *% 0x00010001) & 0xFF0000FF;
    v = (v *% 0x00000101) & 0x0F00F00F;
    v = (v *% 0x00000011) & 0xC30C30C3;
    v = (v *% 0x00000005) & 0x49249249;
    return v;
}

/// Which of the 1024 steps along one axis `value` falls in, over `min` to `max`. A flat axis (min == max) is all in
/// step 0, and anything outside clamps to the end steps
fn Quantize(value: f32, min: f32, max: f32) u32 {
    const extent = max - min;
    if (!(extent > 0)) return 0;
    const t = @min(@max((value - min) / extent, 0.0), 1.0);
    return @min(@as(u32, @intFromFloat(t * MORTON_STEPS)), (1 << MORTON_BITS_PER_AXIS) - 1);
}

/// `point`'s Morton code within `bounds`: its step along x, y and z, their bits interleaved x first (x9 y9 z9 x8 y8
/// z8 ... x0 y0 z0). Sorting by it traces a Z shaped path through space, so items close together sort close together,
/// and a code's top bits say which region it is in: the top bit which half along x, the top two which quarter, and
/// so on, which is where the binary build splits
pub fn MortonCode(point: Vec3(f32), bounds: Aabb) u32 {
    const x = Quantize(point.x, bounds.Min.x, bounds.Max.x);
    const y = Quantize(point.y, bounds.Min.y, bounds.Max.y);
    const z = Quantize(point.z, bounds.Min.z, bounds.Max.z);
    return (SpreadBits(x) << 2) | (SpreadBits(y) << 1) | SpreadBits(z);
}

//==================================the tree==================================

/// Which systems an item is for, so one tree can be shared and each walk passes over what is not its own. A node's
/// mask is the masks of everything under it ORed together, so a walk skips a whole branch of the other system's
/// items in one test. 4 bits, kept in Node.Info
pub const Mask = struct {
    pub const RENDER: u4 = 1 << 0;
    pub const PHYSICS: u4 = 1 << 1;
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
    /// finished with it. The root's is the node count, the end of the walk. Only the CPU's stack free walk (WalkRay)
    /// uses them now; the GPU goes into the nearer child first instead. Until WalkRay does too, for physics
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

/// One item a tree is built over: its Morton code (MortonCode), its box and its mask. A build takes them sorted by
/// code, and a leaf's items are a run of that sorted order, so whatever the items stand for can be kept in the same
/// order and found by a leaf's FirstItem and ItemCount
pub const Item = struct {
    Code: u32,
    Bounds: Aabb,
    Mask: u4,
};

/// The deepest a leaf can be, the root being 0. A walk that goes into the nearer child first keeps the farther one to
/// come back to, at most one per level, so this is how many it can be holding (SDFRayMarcher.NearestByBVH). Build
/// keeps to it by splitting down the middle wherever the Morton split would leave a half too big to fit
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

/// The tree over `items`, which have to be sorted by Code, into `nodes` (cleared first, its memory kept). No
/// recursion: one pass makes the nodes depth first from a list of ranges still to do, one pass forward fills in each
/// node's Skip, and Refit fills in the boxes and masks going back up
pub fn Build(allocator: std.mem.Allocator, items: []const Item, nodes: *std.ArrayList(Node)) !void {
    nodes.clearRetainingCapacity();
    if (items.len == 0) return;
    std.debug.assert(items.len <= MAX_ITEMS);

    //the structure, depth first. A range waiting its turn is a right half, whose parent's Info gets its index once it
    //is made, or the root
    const Pending = struct { First: u32, End: u32, RightOf: ?u32, Depth: u32 };
    var pending: [MAX_BUILD_DEPTH]Pending = undefined;
    var pending_count: usize = 1;
    pending[0] = .{ .First = 0, .End = @intCast(items.len), .RightOf = null, .Depth = 0 };

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
        var split = SplitPoint(items, range.First, range.End);
        //a half too big to fit in the levels left under MAX_DEPTH, the way a long run of codes one bit apart would make,
        //goes down the middle instead, which always fits
        const bigger_half = @max(split - range.First, range.End - split);
        if (range.Depth + 1 + LevelsBelow(bigger_half) > MAX_DEPTH) split = range.First + count / 2;
        std.debug.assert(pending_count + 2 <= MAX_BUILD_DEPTH);
        pending[pending_count] = .{ .First = split, .End = range.End, .RightOf = node_ind, .Depth = range.Depth + 1 };
        pending[pending_count + 1] = .{ .First = range.First, .End = split, .RightOf = null, .Depth = range.Depth + 1 };
        pending_count += 2;
    }

    //where each node's walk goes next. A parent comes before its children, so its own Skip is always set by the time
    //its children's are worked out from it
    nodes.items[0].Skip = @intCast(nodes.items.len);
    for (nodes.items, 0..) |node, node_ind| {
        if (node.IsLeaf()) continue;
        const left = node_ind + 1;
        const right = node.RightChild();
        nodes.items[left].Skip = right;
        nodes.items[right].Skip = node.Skip;
    }

    Refit(items, nodes.items);
}

/// Where a range of items sorted by code splits in two: where their codes' highest differing bit turns from 0 to 1,
/// so each half is one side of a plane through space. Items that all share one code split down the middle instead
fn SplitPoint(items: []const Item, first: u32, end: u32) u32 {
    const first_code = items[first].Code;
    const last_code = items[end - 1].Code;
    if (first_code == last_code) return first + (end - first) / 2;

    //every code in the range shares the bits above this one, so the ones with it set are all at the end
    const split_bit = @as(u32, 1) << @intCast(31 - @clz(first_code ^ last_code));
    var low = first;
    var high = end - 1;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (items[middle].Code & split_bit != 0) high = middle else low = middle + 1;
    }
    return low;
}

/// Each node's box and mask from the items under it, going back up: every node after its children, which come
/// after it. What a build finishes with, and all a tree needs after its items move, as long as it still holds the
/// same items in the same order. Boxes moving far from where they were built make a looser tree, which a rebuild fixes
pub fn Refit(items: []const Item, nodes: []Node) void {
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

    //the branches still to go down, each with its depth. Going down one keeps the other, at most one per level
    const Branch = struct { Node: u32, Depth: u32 };
    var waiting: [MAX_DEPTH + 1]Branch = undefined;
    var waiting_count: usize = 1;
    waiting[0] = .{ .Node = 0, .Depth = 0 };
    while (waiting_count > 0) {
        waiting_count -= 1;
        const branch = waiting[waiting_count];
        const node = nodes[branch.Node];
        if (node.IsLeaf()) {
            stats.Leaves += 1;
            stats.Items += node.ItemCount();
            stats.LeafDepths += branch.Depth;
            stats.Depth = @max(stats.Depth, branch.Depth);
            continue;
        }
        waiting[waiting_count] = .{ .Node = node.RightChild(), .Depth = branch.Depth + 1 };
        waiting[waiting_count + 1] = .{ .Node = branch.Node + 1, .Depth = branch.Depth + 1 };
        waiting_count += 2;
    }
    return stats;
}

/// Walks the tree with a ray, the stack free way, in the tree's own fixed order: into each node whose box the ray
/// reaches within how far is still worth looking and that has any of `mask`, and on to its Skip past any that it does
/// not. Every item of each leaf it reaches is handed to `visitor.Visit(item_index)`, which returns how far along the ray
/// is still worth looking: the nearest hit so far for a nearest hit search, which then passes over every box starting
/// past it, or `max_t` again to see them all. A leaf's items can have different masks, so the visitor checks an item's
/// own if that matters
pub fn WalkRay(nodes: []const Node, ray: Ray, max_t: f32, mask: u32, visitor: anytype) void {
    const inv_dir = Vec3(f32).FromVector(@as(Vec3(f32).VectorT, @splat(1.0)) / ray.Dir.ToVector());
    var reach = max_t;
    var node_ind: u32 = 0;
    while (node_ind < nodes.len) {
        const node = nodes[node_ind];
        const bounds = node.Bounds();
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
            reach = @min(reach, visitor.Visit(@intCast(item_ind)));
        }
        node_ind = node.Skip;
    }
}
