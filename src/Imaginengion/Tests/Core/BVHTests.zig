//! BVH: the tree the renderer (and later physics) builds over its items' boxes. No engine needed. Run with
//! `zig build test`.
const std = @import("std");
const BVH = @import("../../Core/BVH.zig");
const Aabb = @import("../../Math/Aabb.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const RayIntersect = @import("../../Math/RayIntersect.zig");
const Ray = @import("../../Math/CameraRay.zig").Ray;

//==================================Morton ordering==================================

const UNIT_BOUNDS = Aabb{ .Min = .{ .x = 0, .y = 0, .z = 0 }, .Max = .{ .x = 1, .y = 1, .z = 1 } };

test "spreading bits puts bit i at bit 3i" {
    try std.testing.expectEqual(@as(u32, 0), BVH.SpreadBits(0));
    try std.testing.expectEqual(@as(u32, 0b1), BVH.SpreadBits(0b1));
    try std.testing.expectEqual(@as(u32, 0b1001), BVH.SpreadBits(0b11));
    try std.testing.expectEqual(@as(u32, 0b1000000001), BVH.SpreadBits(0b1001));
    //all ten bits: every third bit of the 30
    try std.testing.expectEqual(@as(u32, 0x09249249), BVH.SpreadBits(0x3FF));
    //only the low ten bits are used
    try std.testing.expectEqual(BVH.SpreadBits(0x3FF), BVH.SpreadBits(0xFFFFFFFF));
}

test "a Morton code interleaves the axes x first: the min corner is 0 and the max corner every bit" {
    try std.testing.expectEqual(@as(u32, 0), BVH.MortonCode(.{ .x = 0, .y = 0, .z = 0 }, UNIT_BOUNDS));
    try std.testing.expectEqual(@as(u32, 0x3FFFFFFF), BVH.MortonCode(.{ .x = 1, .y = 1, .z = 1 }, UNIT_BOUNDS));
    //only x at its max: every third bit from the top
    try std.testing.expectEqual(BVH.SpreadBits(0x3FF) << 2, BVH.MortonCode(.{ .x = 1, .y = 0, .z = 0 }, UNIT_BOUNDS));
    try std.testing.expectEqual(BVH.SpreadBits(0x3FF) << 1, BVH.MortonCode(.{ .x = 0, .y = 1, .z = 0 }, UNIT_BOUNDS));
    try std.testing.expectEqual(BVH.SpreadBits(0x3FF), BVH.MortonCode(.{ .x = 0, .y = 0, .z = 1 }, UNIT_BOUNDS));
}

test "a Morton code's top bits say which half, then which quarter, of space a point is in" {
    const top_bit: u32 = 1 << 29;
    const second_bit: u32 = 1 << 28;
    //the top bit is which half along x
    try std.testing.expect(BVH.MortonCode(.{ .x = 0.2, .y = 0.9, .z = 0.9 }, UNIT_BOUNDS) & top_bit == 0);
    try std.testing.expect(BVH.MortonCode(.{ .x = 0.7, .y = 0.1, .z = 0.1 }, UNIT_BOUNDS) & top_bit != 0);
    //the next which half along y
    try std.testing.expect(BVH.MortonCode(.{ .x = 0.7, .y = 0.2, .z = 0.5 }, UNIT_BOUNDS) & second_bit == 0);
    try std.testing.expect(BVH.MortonCode(.{ .x = 0.7, .y = 0.8, .z = 0.5 }, UNIT_BOUNDS) & second_bit != 0);
    //two points in the same eighth of space share the top three bits, whatever else differs
    const a = BVH.MortonCode(.{ .x = 0.6, .y = 0.1, .z = 0.9 }, UNIT_BOUNDS);
    const b = BVH.MortonCode(.{ .x = 0.95, .y = 0.45, .z = 0.55 }, UNIT_BOUNDS);
    try std.testing.expectEqual(a >> 27, b >> 27);
}

test "a flat axis puts everything at its first step instead of dividing by zero" {
    //every shape at the same depth, the way flat UI is
    const flat_z = Aabb{ .Min = .{ .x = 0, .y = 0, .z = 5 }, .Max = .{ .x = 1, .y = 1, .z = 5 } };
    const code = BVH.MortonCode(.{ .x = 1, .y = 1, .z = 5 }, flat_z);
    try std.testing.expectEqual(BVH.SpreadBits(0x3FF) << 2 | BVH.SpreadBits(0x3FF) << 1, code);
}

test "a point outside the bounds clamps to the end steps" {
    try std.testing.expectEqual(@as(u32, 0), BVH.MortonCode(.{ .x = -3, .y = -1, .z = -0.5 }, UNIT_BOUNDS));
    try std.testing.expectEqual(@as(u32, 0x3FFFFFFF), BVH.MortonCode(.{ .x = 4, .y = 2, .z = 9 }, UNIT_BOUNDS));
}

test "sorting by Morton code keeps the points of each quarter of a plane together" {
    //a 4x4 grid of points on the z = 0 plane, given in row order: sorted by code, each 2x2 quarter's four points
    //come out next to each other
    var codes: [16]struct { code: u32, quarter: u32 } = undefined;
    for (0..4) |row| {
        for (0..4) |col| {
            const point = Vec3(f32){ .x = (@as(f32, @floatFromInt(col)) + 0.5) / 4, .y = (@as(f32, @floatFromInt(row)) + 0.5) / 4, .z = 0 };
            codes[row * 4 + col] = .{ .code = BVH.MortonCode(point, UNIT_BOUNDS), .quarter = @intCast((col / 2) + 2 * (row / 2)) };
        }
    }
    std.mem.sort(@TypeOf(codes[0]), &codes, {}, struct {
        fn lessThan(_: void, a: @TypeOf(codes[0]), b: @TypeOf(codes[0])) bool {
            return a.code < b.code;
        }
    }.lessThan);
    for (0..4) |quarter| {
        for (codes[quarter * 4 .. quarter * 4 + 4]) |entry| try std.testing.expectEqual(codes[quarter * 4].quarter, entry.quarter);
    }
}

//==================================the tree==================================

/// `count` random boxes in a 20 unit cube, some of them flat plates like quads, with their Morton codes, sorted by
/// code the way a build takes them. All RENDER
fn RandomItems(random: std.Random, count: usize) ![]BVH.Item {
    const items = try std.testing.allocator.alloc(BVH.Item, count);
    var centers = Aabb.empty;
    for (items, 0..) |*item, i| {
        const center = Vec3(f32){ .x = random.float(f32) * 20 - 10, .y = random.float(f32) * 20 - 10, .z = random.float(f32) * 20 - 10 };
        const half = Vec3(f32){
            .x = 0.05 + random.float(f32) * 1.5,
            .y = 0.05 + random.float(f32) * 1.5,
            .z = if (i % 3 == 0) 0.001 else 0.05 + random.float(f32) * 1.5,
        };
        item.* = .{ .Code = 0, .Bounds = .{ .Min = center.SubVec(half), .Max = center.AddVec(half) }, .Mask = BVH.Mask.RENDER };
        centers = centers.Union(.{ .Min = center, .Max = center });
    }
    for (items) |*item| item.Code = BVH.MortonCode(item.Bounds.Center(), centers);
    std.mem.sort(BVH.Item, items, {}, struct {
        fn lessThan(_: void, a: BVH.Item, b: BVH.Item) bool {
            return a.Code < b.Code;
        }
    }.lessThan);
    return items;
}

fn ContainsBox(outer: Aabb, inner: Aabb) bool {
    return outer.Contains(inner.Min) and outer.Contains(inner.Max);
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

fn BuildTree(items: []const BVH.Item) !std.ArrayList(BVH.Node) {
    var nodes: std.ArrayList(BVH.Node) = .empty;
    try BVH.Build(std.testing.allocator, items, &nodes);
    return nodes;
}

test "a tree over no items has no nodes, and one over a single item is one leaf" {
    var empty_nodes = try BuildTree(&.{});
    defer empty_nodes.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), empty_nodes.items.len);

    const one = [_]BVH.Item{.{ .Code = 0, .Bounds = UNIT_BOUNDS, .Mask = BVH.Mask.RENDER }};
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

test "items that all share one Morton code still build a valid tree, split down the middle" {
    var items: [37]BVH.Item = undefined;
    for (&items, 0..) |*item, i| {
        const x: f32 = @floatFromInt(i);
        item.* = .{ .Code = 0, .Bounds = .{ .Min = .{ .x = x, .y = 0, .z = 0 }, .Max = .{ .x = x + 1, .y = 1, .z = 1 } }, .Mask = BVH.Mask.RENDER };
    }
    var nodes = try BuildTree(&items);
    defer nodes.deinit(std.testing.allocator);
    try ExpectValidTree(&items, nodes.items);
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
