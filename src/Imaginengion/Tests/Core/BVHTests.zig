//! BVH: the tree the renderer (and later physics) builds over its items' boxes. No engine needed. Run with
//! `zig build test`.
const std = @import("std");
const BVH = @import("../../Core/BVH.zig");
const Aabb = @import("../../Math/Aabb.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const RayIntersect = @import("../../Math/RayIntersect.zig");
const Ray = @import("../../Math/CameraRay.zig").Ray;

const UNIT_BOUNDS = Aabb{ .Min = .{ .x = 0, .y = 0, .z = 0 }, .Max = .{ .x = 1, .y = 1, .z = 1 } };

/// A box `half` out from `center` every way
fn BoxAt(center: Vec3(f32), half: f32) Aabb {
    return .{ .Min = center.SubVec(.FromScalar(half)), .Max = center.AddVec(.FromScalar(half)) };
}

/// `count` random boxes in a 20 unit cube, some of them flat plates like quads, each Id its place. All RENDER
fn RandomItems(random: std.Random, count: usize) ![]BVH.Item {
    const items = try std.testing.allocator.alloc(BVH.Item, count);
    for (items, 0..) |*item, i| {
        const center = Vec3(f32){ .x = random.float(f32) * 20 - 10, .y = random.float(f32) * 20 - 10, .z = random.float(f32) * 20 - 10 };
        const half = Vec3(f32){
            .x = 0.05 + random.float(f32) * 1.5,
            .y = 0.05 + random.float(f32) * 1.5,
            .z = if (i % 3 == 0) 0.001 else 0.05 + random.float(f32) * 1.5,
        };
        item.* = .{ .Id = @intCast(i), .Bounds = .{ .Min = center.SubVec(half), .Max = center.AddVec(half) }, .Mask = BVH.Mask.RENDER };
    }
    return items;
}

/// Everything a built tree has to be: every item in exactly one leaf, the leaves covering the items in order, no leaf
/// over MAX_LEAF_ITEMS, every Skip leading just past its node's subtree, and every box and mask exactly that of
/// everything under it
fn ExpectValidTree(items: []const BVH.Item, nodes: []const BVH.Node) !void {
    if (items.len == 0) return std.testing.expectEqual(@as(usize, 0), nodes.len);
    try std.testing.expectEqual(@as(u32, @intCast(nodes.len)), nodes[0].Skip);

    //each subtree's size, back to front since children come after their parent. An inner node's right child starts
    //just after its left child's whole subtree, and every Skip is just past its own
    const sizes = try std.testing.allocator.alloc(u32, nodes.len);
    defer std.testing.allocator.free(sizes);
    var node_ind = nodes.len;
    while (node_ind > 0) {
        node_ind -= 1;
        const node = nodes[node_ind];
        if (node.IsLeaf()) {
            sizes[node_ind] = 1;
        } else {
            try std.testing.expectEqual(@as(u32, @intCast(node_ind + 1)) + sizes[node_ind + 1], node.RightChild());
            sizes[node_ind] = 1 + sizes[node_ind + 1] + sizes[node.RightChild()];
        }
    }
    for (nodes, 0..) |node, i| try std.testing.expectEqual(@as(u32, @intCast(i)) + sizes[i], node.Skip);

    var next_item: u32 = 0;
    for (nodes, 0..) |node, i| {
        var bounds = Aabb.empty;
        var mask: u32 = 0;
        if (node.IsLeaf()) {
            try std.testing.expectEqual(next_item, node.FirstItem());
            try std.testing.expect(node.ItemCount() >= 1 and node.ItemCount() <= BVH.MAX_LEAF_ITEMS);
            next_item += node.ItemCount();
            for (items[node.FirstItem()..][0..node.ItemCount()]) |item| {
                bounds = bounds.Union(item.Bounds);
                mask |= item.Mask;
            }
        } else {
            const left = nodes[i + 1];
            const right = nodes[node.RightChild()];
            bounds = left.Bounds().Union(right.Bounds());
            mask = left.ItemMask() | right.ItemMask();
        }
        try std.testing.expectEqual(bounds, node.Bounds());
        try std.testing.expectEqual(mask, node.ItemMask());
    }
    try std.testing.expectEqual(@as(u32, @intCast(items.len)), next_item);
}

fn BuildTree(items: []BVH.Item) !std.ArrayList(BVH.Node) {
    var nodes: std.ArrayList(BVH.Node) = .empty;
    try BVH.Build(std.testing.allocator, items, &nodes);
    return nodes;
}

test "a tree over no items has no nodes, and one over a single item is one leaf" {
    var empty_nodes = try BuildTree(&.{});
    defer empty_nodes.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), empty_nodes.items.len);

    var one = [_]BVH.Item{.{ .Id = 0, .Bounds = UNIT_BOUNDS, .Mask = BVH.Mask.RENDER }};
    var nodes = try BuildTree(&one);
    defer nodes.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), nodes.items.len);
    try ExpectValidTree(&one, nodes.items);
}

test "a built tree holds every item once, in small leaves, with every box exactly around what is under it" {
    var prng = std.Random.DefaultPrng.init(0xB0C5);
    for ([_]usize{ 2, 4, 5, 17, 64, 300 }) |count| {
        const items = try RandomItems(prng.random(), count);
        defer std.testing.allocator.free(items);
        var nodes = try BuildTree(items);
        defer nodes.deinit(std.testing.allocator);
        try ExpectValidTree(items, nodes.items);
    }
}

test "the build reorders the items, each carrying its Id along with its box and mask" {
    var prng = std.Random.DefaultPrng.init(0x1D5);
    const items = try RandomItems(prng.random(), 200);
    defer std.testing.allocator.free(items);
    for (items, 0..) |*item, i| item.Mask = if (i % 2 == 0) BVH.Mask.RENDER else BVH.Mask.PHYSICS;
    const before = try std.testing.allocator.dupe(BVH.Item, items);
    defer std.testing.allocator.free(before);

    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);
    var seen = try std.DynamicBitSetUnmanaged.initEmpty(std.testing.allocator, items.len);
    defer seen.deinit(std.testing.allocator);
    var moved: usize = 0;
    for (items, 0..) |item, i| {
        try std.testing.expect(!seen.isSet(item.Id));
        seen.set(item.Id);
        try std.testing.expectEqualDeep(before[item.Id], item);
        moved += @intFromBool(item.Id != i);
    }
    try std.testing.expectEqual(items.len, seen.count());
    //200 random boxes don't come out in the order they went in
    try std.testing.expect(moved > 0);
}

test "the same items in the same order build the same tree" {
    var prng = std.Random.DefaultPrng.init(0x5A3E);
    const items = try RandomItems(prng.random(), 150);
    defer std.testing.allocator.free(items);
    const again = try std.testing.allocator.dupe(BVH.Item, items);
    defer std.testing.allocator.free(again);

    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);
    var nodes_again = try BuildTree(again);
    defer nodes_again.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(BVH.Node, nodes.items, nodes_again.items);
    for (items, again) |item, item_again| try std.testing.expectEqual(item.Id, item_again.Id);
}

test "items whose centers are all in one spot still build a valid tree, split down the middle" {
    //boxes of every size around the origin, whose centers come out exactly 0
    var items: [37]BVH.Item = undefined;
    for (&items, 0..) |*item, i| {
        item.* = .{ .Id = @intCast(i), .Bounds = BoxAt(.{ .x = 0, .y = 0, .z = 0 }, 0.1 + @as(f32, @floatFromInt(i))), .Mask = BVH.Mask.RENDER };
    }
    var nodes = try BuildTree(&items);
    defer nodes.deinit(std.testing.allocator);
    try ExpectValidTree(&items, nodes.items);
    try std.testing.expectEqual(@as(u32, 4), Depth(nodes.items));
}

test "a cluster in the middle of the others is kept whole in a subtree of its own, not cut where space halves" {
    //three tight clusters of 8 along x, the middle one right where the space they span halves, which is where cutting
    //space down the middle would split it, leaving both halves' boxes reaching across from one end cluster to it
    var items: [24]BVH.Item = undefined;
    for (&items, 0..) |*item, i| {
        const cluster: f32 = @floatFromInt(i / 8);
        const spot: f32 = @floatFromInt(i % 8);
        const center = Vec3(f32){ .x = cluster * 5 + (spot - 3.5) * 0.03, .y = @mod(spot, 3) * 0.04, .z = 0 };
        item.* = .{ .Id = @intCast(i), .Bounds = BoxAt(center, 0.05), .Mask = BVH.Mask.RENDER };
    }
    var nodes = try BuildTree(&items);
    defer nodes.deinit(std.testing.allocator);
    try ExpectValidTree(&items, nodes.items);

    //every cluster is exactly the items under some node: a box around it and nothing else
    for (0..3) |cluster| {
        var found = false;
        for (0..nodes.items.len) |node_ind| {
            const range = SubtreeItems(nodes.items, @intCast(node_ind));
            if (range.End - range.First != 8) continue;
            var all_in_cluster = true;
            for (items[range.First..range.End]) |item| all_in_cluster = all_in_cluster and item.Id / 8 == cluster;
            found = found or all_in_cluster;
        }
        try std.testing.expect(found);
    }
}

/// The run of items under node `node_ind`: from its leftmost leaf's first to its rightmost leaf's last
fn SubtreeItems(nodes: []const BVH.Node, node_ind: u32) struct { First: u32, End: u32 } {
    var leftmost = node_ind;
    while (!nodes[leftmost].IsLeaf()) leftmost += 1;
    var rightmost = node_ind;
    while (!nodes[rightmost].IsLeaf()) rightmost = nodes[rightmost].RightChild();
    return .{ .First = nodes[leftmost].FirstItem(), .End = nodes[rightmost].FirstItem() + nodes[rightmost].ItemCount() };
}

/// How deep the tree's deepest leaf is, the root being 0
fn Depth(nodes: []const BVH.Node) u32 {
    var deepest: u32 = 0;
    var waiting: [64]struct { Node: u32, Depth: u32 } = undefined;
    var waiting_count: usize = 1;
    waiting[0] = .{ .Node = 0, .Depth = 0 };
    while (waiting_count > 0) {
        waiting_count -= 1;
        const at = waiting[waiting_count];
        const node = nodes[at.Node];
        if (node.IsLeaf()) {
            deepest = @max(deepest, at.Depth);
            continue;
        }
        waiting[waiting_count] = .{ .Node = at.Node + 1, .Depth = at.Depth + 1 };
        waiting[waiting_count + 1] = .{ .Node = node.RightChild(), .Depth = at.Depth + 1 };
        waiting_count += 2;
    }
    return deepest;
}

test "items each much further out than the last, which would peel off one at a time, still build no deeper than MAX_DEPTH" {
    //along each axis, items 32 times further out each time: so far out that every other center along it lands in
    //the first of the 16 bins, so the only split there is is the furthest one alone. Then 20 more at the middle. That
    //is a chain about 40 levels long before the middle ones even start splitting
    const STEPS = 13;
    var items: [3 * STEPS + 20]BVH.Item = undefined;
    for (&items, 0..) |*item, i| {
        var center = Vec3(f32){ .x = 0, .y = 0, .z = 0 };
        if (i < 3 * STEPS) {
            const out = std.math.pow(f32, 32, @floatFromInt(i % STEPS));
            switch (i / STEPS) {
                0 => center.x = out,
                1 => center.y = out,
                else => center.z = out,
            }
        }
        item.* = .{ .Id = @intCast(i), .Bounds = BoxAt(center, 0.25), .Mask = BVH.Mask.RENDER };
    }
    var nodes = try BuildTree(&items);
    defer nodes.deinit(std.testing.allocator);
    try ExpectValidTree(&items, nodes.items);
    try std.testing.expect(Depth(nodes.items) <= BVH.MAX_DEPTH);
}

test "a tree's stats count its nodes, leaves and items, and how deep its leaves are" {
    var empty_nodes = try BuildTree(&.{});
    defer empty_nodes.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(BVH.TreeStats{}, BVH.Stats(empty_nodes.items));

    //one leaf: the root, at depth 0. A ray through it tests its box and its 3 items
    var three = [_]BVH.Item{
        .{ .Id = 0, .Bounds = UNIT_BOUNDS, .Mask = BVH.Mask.RENDER },
        .{ .Id = 1, .Bounds = UNIT_BOUNDS, .Mask = BVH.Mask.RENDER },
        .{ .Id = 2, .Bounds = UNIT_BOUNDS, .Mask = BVH.Mask.RENDER },
    };
    var leaf_nodes = try BuildTree(&three);
    defer leaf_nodes.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(BVH.TreeStats{ .Nodes = 1, .Leaves = 1, .Depth = 0, .LeafDepths = 0, .Items = 3, .Cost = 4 }, BVH.Stats(leaf_nodes.items));

    var prng = std.Random.DefaultPrng.init(0x57A7);
    const items = try RandomItems(prng.random(), 300);
    defer std.testing.allocator.free(items);
    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);
    const stats = BVH.Stats(nodes.items);
    try std.testing.expectEqual(@as(u32, 300), stats.Items);
    //every inner node has two children, so a binary tree has one fewer of them than it has leaves
    try std.testing.expectEqual(stats.Nodes, 2 * stats.Leaves - 1);
    try std.testing.expectEqual(Depth(nodes.items), stats.Depth);
    try std.testing.expect(stats.AverageLeafDepth() > 0 and stats.AverageLeafDepth() <= @as(f32, @floatFromInt(stats.Depth)));
    try std.testing.expect(stats.AverageLeafItems() > 0 and stats.AverageLeafItems() <= @as(f32, @floatFromInt(BVH.MAX_LEAF_ITEMS)));
}

test "a tree's cost counts each box and item by the chance a ray through the root goes through it" {
    //two leaves of 4 unit cubes, 10 apart along x: the root's box is 11 x 1 x 1, half its surface 11 + 1 + 11 = 23,
    //and each leaf's 3. A ray tests the root's box, then both children's, then each leaf's 4 items 3/23 of the time
    var items: [8]BVH.Item = undefined;
    for (&items, 0..) |*item, i| {
        const x: f32 = if (i < 4) 0 else 10;
        item.* = .{ .Id = @intCast(i), .Bounds = BoxAt(.{ .x = x, .y = 0, .z = 0 }, 0.5), .Mask = BVH.Mask.RENDER };
    }
    var nodes = try BuildTree(&items);
    defer nodes.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), nodes.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1 + 2 + 2 * (3.0 / 23.0) * 4), BVH.Stats(nodes.items).Cost, 0.0001);
}

test "a refit after items move keeps every box exactly around what is under it" {
    var prng = std.Random.DefaultPrng.init(0x4EF1);
    const items = try RandomItems(prng.random(), 120);
    defer std.testing.allocator.free(items);
    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);

    //every item moves somewhere else, a different size
    for (items) |*item| {
        const shift = Vec3(f32){ .x = prng.random().float(f32) * 6 - 3, .y = prng.random().float(f32) * 6 - 3, .z = prng.random().float(f32) * 6 - 3 };
        item.Bounds = .{ .Min = item.Bounds.Min.AddVec(shift), .Max = item.Bounds.Max.AddVec(shift).AddVec(.FromScalar(prng.random().float(f32))) };
    }
    BVH.Refit(items, nodes.items);
    try ExpectValidTree(items, nodes.items);
}

/// Hands every item a walk reaches to a set, and keeps looking as far as it started
const CollectVisitor = struct {
    Visited: std.DynamicBitSetUnmanaged,
    MaxT: f32,

    pub fn Visit(self: *CollectVisitor, item: u32) f32 {
        self.Visited.set(item);
        return self.MaxT;
    }
};

/// Tests each item a walk reaches against the ray, keeping the nearest hit, and only looks as far as that from then on
const NearestVisitor = struct {
    Items: []const BVH.Item,
    Ray: Ray,
    InvDir: Vec3(f32),
    Nearest: f32,

    pub fn Visit(self: *NearestVisitor, item: u32) f32 {
        const bounds = self.Items[item].Bounds;
        if (RayIntersect.RayAabb(self.Ray.Origin, self.InvDir, bounds.Min, bounds.Max)) |span| {
            self.Nearest = @min(self.Nearest, @max(span.Enter, 0));
        }
        return self.Nearest;
    }
};

fn RandomRay(random: std.Random) Ray {
    const origin = Vec3(f32){ .x = random.float(f32) * 30 - 15, .y = random.float(f32) * 30 - 15, .z = random.float(f32) * 30 - 15 };
    const dir = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
    return .{ .Origin = origin, .Dir = dir.Dir() };
}

fn InvDir(ray: Ray) Vec3(f32) {
    return .FromVector(@as(Vec3(f32).VectorT, @splat(1.0)) / ray.Dir.ToVector());
}

test "a ray walk reaches every item whose box the ray goes through, and finds the same nearest one as testing them all" {
    var prng = std.Random.DefaultPrng.init(0x7A1C);
    const items = try RandomItems(prng.random(), 250);
    defer std.testing.allocator.free(items);
    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);
    const max_t: f32 = 100;

    var hits: usize = 0;
    for (0..400) |_| {
        const ray = RandomRay(prng.random());
        const inv_dir = InvDir(ray);

        //by testing every item
        var brute_nearest = std.math.inf(f32);
        var collect = CollectVisitor{ .Visited = try .initEmpty(std.testing.allocator, items.len), .MaxT = max_t };
        defer collect.Visited.deinit(std.testing.allocator);
        BVH.WalkRay(nodes.items, ray, max_t, BVH.Mask.RENDER, &collect);
        for (items, 0..) |item, i| {
            const span = RayIntersect.RayAabb(ray.Origin, inv_dir, item.Bounds.Min, item.Bounds.Max) orelse continue;
            if (span.Enter > max_t) continue;
            //nothing the ray goes through is left out
            try std.testing.expect(collect.Visited.isSet(i));
            brute_nearest = @min(brute_nearest, @max(span.Enter, 0));
            hits += 1;
        }

        var nearest = NearestVisitor{ .Items = items, .Ray = ray, .InvDir = inv_dir, .Nearest = max_t };
        BVH.WalkRay(nodes.items, ray, max_t, BVH.Mask.RENDER, &nearest);
        if (brute_nearest == std.math.inf(f32)) {
            try std.testing.expectEqual(max_t, nearest.Nearest);
        } else {
            try std.testing.expectApproxEqAbs(brute_nearest, nearest.Nearest, 0.00001);
        }
    }
    try std.testing.expect(hits > 200);
}

test "a walk passes over branches with none of its mask" {
    //physics only items: a render walk finds nothing however many boxes the ray goes through, and a physics walk
    //finds them all
    var prng = std.Random.DefaultPrng.init(0x3A5C);
    const items = try RandomItems(prng.random(), 60);
    defer std.testing.allocator.free(items);
    for (items) |*item| item.Mask = BVH.Mask.PHYSICS;
    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);

    const through_all = Ray{ .Origin = .{ .x = -50, .y = 0, .z = 0 }, .Dir = .{ .x = 1, .y = 0, .z = 0 } };
    var render = CollectVisitor{ .Visited = try .initEmpty(std.testing.allocator, items.len), .MaxT = 1000 };
    defer render.Visited.deinit(std.testing.allocator);
    BVH.WalkRay(nodes.items, through_all, 1000, BVH.Mask.RENDER, &render);
    try std.testing.expectEqual(@as(usize, 0), render.Visited.count());

    //the root's mask says what is anywhere under it
    try std.testing.expectEqual(@as(u32, BVH.Mask.PHYSICS), nodes.items[0].ItemMask());
}

test "a box walk reaches every item whose box overlaps the query and has the mask, and an item of another mask never" {
    var prng = std.Random.DefaultPrng.init(0xB0B5);
    const random = prng.random();
    const items = try RandomItems(random, 300);
    defer std.testing.allocator.free(items);
    //half the items physics' instead, so whole branches can be skipped by mask
    for (items, 0..) |*item, i| item.Mask = if (i % 2 == 0) BVH.Mask.RENDER else BVH.Mask.PHYSICS;
    var nodes = try BuildTree(items);
    defer nodes.deinit(std.testing.allocator);

    const Collect = struct {
        mItems: []const BVH.Item,
        mBox: Aabb,
        mFound: std.ArrayList(u32) = .empty,

        pub fn Visit(self: *@This(), item_ind: u32) !void {
            const item = self.mItems[item_ind];
            if (item.Mask & BVH.Mask.PHYSICS == 0 or !item.Bounds.Overlaps(self.mBox)) return;
            try self.mFound.append(std.testing.allocator, item.Id);
        }
    };

    var queries_with_hits: usize = 0;
    for (0..200) |_| {
        const center = Vec3(f32){ .x = random.float(f32) * 24 - 12, .y = random.float(f32) * 24 - 12, .z = random.float(f32) * 24 - 12 };
        const box = BoxAt(center, 0.1 + random.float(f32) * 3);

        var collect = Collect{ .mItems = items, .mBox = box };
        defer collect.mFound.deinit(std.testing.allocator);
        try BVH.WalkBox(nodes.items, box, BVH.Mask.PHYSICS, &collect);

        //what trying every item finds
        var expected: std.ArrayList(u32) = .empty;
        defer expected.deinit(std.testing.allocator);
        for (items) |item| {
            if (item.Mask & BVH.Mask.PHYSICS != 0 and item.Bounds.Overlaps(box)) try expected.append(std.testing.allocator, item.Id);
        }
        std.sort.pdq(u32, collect.mFound.items, {}, std.sort.asc(u32));
        std.sort.pdq(u32, expected.items, {}, std.sort.asc(u32));
        try std.testing.expectEqualSlices(u32, expected.items, collect.mFound.items);
        if (expected.items.len > 0) queries_with_hits += 1;
    }
    //the queries weren't all misses
    try std.testing.expect(queries_with_hits > 50);
}

test "boxes overlap when they share any point, edges touching included" {
    const a = BoxAt(.{ .x = 0, .y = 0, .z = 0 }, 1);
    try std.testing.expect(a.Overlaps(BoxAt(.{ .x = 2, .y = 0, .z = 0 }, 1)));
    try std.testing.expect(!a.Overlaps(BoxAt(.{ .x = 2.01, .y = 0, .z = 0 }, 1)));
    try std.testing.expect(!a.Overlaps(BoxAt(.{ .x = 0, .y = 0, .z = -2.5 }, 1)));
    try std.testing.expect(a.Grow(0.5).Overlaps(BoxAt(.{ .x = 0, .y = 0, .z = -2.5 }, 1)));
}
