//! Replays an editor BVH dump (F7, Renderer/BVHDump.zig) offline: fires the dumped overlay pass's rays the way
//! SDFRayMarcher.NearestByBVH walks them, and reports where the box tests go. A debugging aid, not a check: it is
//! skipped unless a dump is there (BVHDump.FILE_NAME, in the folder the tests run in or in zig-out/bin), and prints
//! its report when one is. Delete the dump to quiet it. Run with `zig build test`.
//!
//! What it can't know from a dump: masks (no programs in it) and whether a glyph's letter covers the spot (no atlas).
//! It takes every quad and merge hit as drawn and every glyph hit as a gap in its letter, which is what most of a
//! menu's pixels are: background between the letters
const std = @import("std");
const BVH = @import("../../Core/BVH.zig");
const BVHDump = @import("../../Renderer/BVHDump.zig");
const ShapeData = @import("../../Renderer/Renderer2D.zig").ShapeData;
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const CameraRay = @import("../../Math/CameraRay.zig");
const Ray = CameraRay.Ray;
const RayIntersect = @import("../../Math/RayIntersect.zig");
const SDFFunc = @import("../../Math/SDFFunctions.zig");

/// The marcher's let off for a box starting just past the nearest hit (SDFRayMarcher.BVH_BOX_SLACK)
const BOX_SLACK: f32 = 4.0 * std.math.floatEps(f32);
/// Every this many pixels across and down is replayed
const PIXEL_STEP = 2;

/// Why the walk tested a node's box, worked out once the ray's nearest hit is known
const Visit = enum {
    /// the box holds the shape the ray ends on, or one it hits in front of that: it had to be looked in
    Needed,
    /// went in: its box starts in front of the final hit, but nothing in it the ray hits is. Something in front in
    /// the box is somewhere else on screen
    BoxReachesInFront,
    /// went in only because the walk hadn't found the final hit yet when it got to it: its box starts behind it
    BeforeHitFound,
    /// tested and not gone into: missed, or passed over as behind the nearest so far
    Skipped,
};

const Replay = struct {
    Dump: BVHDump.Dump,
    /// each node's shapes' run: from its leftmost leaf's first to its rightmost leaf's last
    Runs: []const struct { First: u32, End: u32 },

    fn Hit(ray: Ray, shape: ShapeData) ?f32 {
        const hit = switch (shape.Type) {
            .Quad => SDFFunc.rayIMQuad(ray, shape),
            .Glyph => SDFFunc.rayIMGlyph(ray, shape),
            .Merge => SDFFunc.rayIMMerge(ray, shape),
            .Box => SDFFunc.rayIMBox(ray, shape),
            .Sphere => SDFFunc.rayIMSphere(ray, shape),
            .None => return null,
        };
        if (!hit.IsHit() or hit.StartedInside) return null;
        //a solid is drawn on every face, a plate only on its front and back
        if (shape.Type == .Box or shape.Type == .Sphere) return hit.T;
        const face = hit.Face orelse return null;
        if (face != .PosZ and face != .NegZ) return null;
        return hit.T;
    }

    fn Drawn(shape: ShapeData) bool {
        return shape.Type != .Glyph;
    }

    fn Enter(ray: Ray, inv_dir: Vec3(f32), node: BVH.Node, nearest_t: f32) ?f32 {
        const bounds = node.Bounds();
        const span = RayIntersect.RayAabb(ray.Origin, inv_dir, bounds.Min, bounds.Max) orelse return null;
        const slack = BOX_SLACK * @max(1.0, @abs(nearest_t));
        return if (span.Enter <= nearest_t + slack) span.Enter else null;
    }

    const Walked = struct {
        NodeTests: u32 = 0,
        ShapeTests: u32 = 0,
        /// the node tests by why (Visit)
        Why: std.EnumArray(Visit, u32) = .initFill(0),
        FinalT: f32 = 0,
        FinalShape: ?u32 = null,
    };

    /// One ray, walked the way NearestByBVH does: into the nearer child first, the farther one waiting, each leaf's
    /// shapes nearest first. Then each node it went into is put down to why
    fn Walk(self: Replay, ray: Ray, skip_shape: ?u32, entered: *std.ArrayList(u32)) Walked {
        const nodes = self.Dump.Nodes;
        const shapes = self.Dump.Shapes;
        var walked = Walked{};
        entered.clearRetainingCapacity();

        var nearest_t = self.Dump.Camera.mPerspectiveFar;
        var nearest_shape: ?u32 = null;
        const inv_dir = Vec3(f32).FromVector(@as(Vec3(f32).VectorT, @splat(1.0)) / ray.Dir.ToVector());
        var waiting: [BVH.MAX_DEPTH]u32 = undefined;
        var waiting_count: u32 = 0;

        walked.NodeTests += 1;
        if (nodes.len == 0 or Enter(ray, inv_dir, nodes[0], nearest_t) == null) return walked;
        var node_ind: u32 = 0;
        while (true) {
            if (entered.items.len < entered.capacity) entered.appendAssumeCapacity(node_ind);
            const node = nodes[node_ind];
            if (node.IsLeaf()) {
                //nearest first, the first drawn one wins
                var hits: [BVH.MAX_LEAF_ITEMS]struct { T: f32, Shape: u32 } = undefined;
                var hit_count: usize = 0;
                for (node.FirstItem()..node.FirstItem() + node.ItemCount()) |shape_ind| {
                    if (skip_shape == @as(u32, @intCast(shape_ind))) continue;
                    walked.ShapeTests += 1;
                    const t = Hit(ray, shapes[shape_ind]) orelse continue;
                    if (t < nearest_t) {
                        hits[hit_count] = .{ .T = t, .Shape = @intCast(shape_ind) };
                        hit_count += 1;
                    }
                }
                std.mem.sort(@TypeOf(hits[0]), hits[0..hit_count], {}, struct {
                    fn lessThan(_: void, a: @TypeOf(hits[0]), b: @TypeOf(hits[0])) bool {
                        return a.T < b.T;
                    }
                }.lessThan);
                for (hits[0..hit_count]) |hit| {
                    if (Drawn(shapes[hit.Shape])) {
                        nearest_t = hit.T;
                        nearest_shape = hit.Shape;
                        break;
                    }
                }
            } else {
                const left_ind = node_ind + 1;
                const right_ind = node.RightChild();
                walked.NodeTests += 2;
                const left_enter = Enter(ray, inv_dir, nodes[left_ind], nearest_t);
                const right_enter = Enter(ray, inv_dir, nodes[right_ind], nearest_t);
                if (left_enter) |left| {
                    if (right_enter) |right| {
                        const left_first = left <= right;
                        waiting[waiting_count] = if (left_first) right_ind else left_ind;
                        waiting_count += 1;
                        node_ind = if (left_first) left_ind else right_ind;
                    } else node_ind = left_ind;
                    continue;
                }
                if (right_enter != null) {
                    node_ind = right_ind;
                    continue;
                }
            }
            while (waiting_count > 0) {
                waiting_count -= 1;
                const next = waiting[waiting_count];
                walked.NodeTests += 1;
                if (Enter(ray, inv_dir, nodes[next], nearest_t) != null) {
                    node_ind = next;
                    break;
                }
            } else break;
        }

        walked.FinalT = nearest_t;
        walked.FinalShape = nearest_shape;
        //every test of a node that wasn't then gone into was a skip; each one gone into is put down to why
        for (entered.items) |entered_ind| {
            walked.Why.getPtr(self.WhyEntered(ray, inv_dir, entered_ind, nearest_t, nearest_shape)).* += 1;
        }
        walked.Why.getPtr(.Skipped).* += walked.NodeTests -| @as(u32, @intCast(entered.items.len));
        return walked;
    }

    fn WhyEntered(self: Replay, ray: Ray, inv_dir: Vec3(f32), node_ind: u32, final_t: f32, final_shape: ?u32) Visit {
        const run = self.Runs[node_ind];
        for (self.Dump.Shapes[run.First..run.End], run.First..) |shape, shape_ind| {
            if (final_shape == @as(u32, @intCast(shape_ind))) return .Needed;
            const t = Hit(ray, shape) orelse continue;
            if (t < final_t) return .Needed;
        }
        const bounds = self.Dump.Nodes[node_ind].Bounds();
        const span = RayIntersect.RayAabb(ray.Origin, inv_dir, bounds.Min, bounds.Max).?;
        return if (span.Enter <= final_t + BOX_SLACK * @max(1.0, @abs(final_t))) .BoxReachesInFront else .BeforeHitFound;
    }
};

fn ReadDump(allocator: std.mem.Allocator) !?BVHDump.Dump {
    const io = std.testing.io;
    for ([_][]const u8{ BVHDump.FILE_NAME, "zig-out/bin/" ++ BVHDump.FILE_NAME }) |path| {
        const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        return try BVHDump.Read(allocator, contents);
    }
    return null;
}

test "a dump reads back as it was written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const shape = ShapeData{
        .AxisX = .{ 1, 0, 0, -2 },
        .AxisY = .{ 0, 1, 0, 0.5 },
        .AxisZ = .{ 0, 0, 1, 100.001 },
        .Size = .{ 3, 0.25, 0.0001 },
        .Params = .{ 0.1, 0.1, 0, 0 },
        .Type = .Glyph,
        .MaskIndex = 7,
        .SurfaceIndex = 42,
        .Flags = ShapeData.FLAG_TRANSPARENT,
    };
    var items = [_]BVH.Item{.{ .Id = 0, .Bounds = SDFFunc.aabbIMShape(shape), .Mask = BVH.Mask.RENDER }};
    var nodes: std.ArrayList(BVH.Node) = .empty;
    defer nodes.deinit(std.testing.allocator);
    try BVH.Build(std.testing.allocator, &items, &nodes);
    var camera = std.mem.zeroes(@FieldType(BVHDump.Dump, "Camera"));
    camera.mPosition = .{ 1, 2, 3 };
    camera.mRotation = .{ 0, 0, 0, 1 };
    camera.mViewportWidth = 1920;
    const dump = BVHDump.Dump{ .Camera = camera, .Shapes = &.{shape}, .Nodes = nodes.items };

    var out: std.Io.Writer.Allocating = .init(arena.allocator());
    try std.json.Stringify.value(dump, .{}, &out.writer);
    const back = try BVHDump.Read(arena.allocator(), out.written());
    try std.testing.expectEqualDeep(dump.Camera, back.Camera);
    try std.testing.expectEqualDeep(dump.Shapes, back.Shapes);
    try std.testing.expectEqualSlices(BVH.Node, dump.Nodes, back.Nodes);
}

test "replay the editor's BVH dump, if there is one, and report where its box tests go" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const dump = (try ReadDump(allocator)) orelse return error.SkipZigTest;
    const camera = dump.Camera;
    const nodes = dump.Nodes;

    const runs = try allocator.alloc(@typeInfo(@FieldType(Replay, "Runs")).pointer.child, nodes.len);
    for (runs, 0..) |*run, node_ind| {
        var leftmost = node_ind;
        while (!nodes[leftmost].IsLeaf()) leftmost += 1;
        var rightmost: u32 = @intCast(node_ind);
        while (!nodes[rightmost].IsLeaf()) rightmost = nodes[rightmost].RightChild();
        run.* = .{ .First = nodes[leftmost].FirstItem(), .End = nodes[rightmost].FirstItem() + nodes[rightmost].ItemCount() };
    }
    const replay = Replay{ .Dump = dump, .Runs = runs };
    const pose = CameraRay.Pose{ .Position = .FromArray(camera.mPosition), .Rotation = .FromArray(camera.mRotation) };
    const params = CameraRay.RayParams{ .Scale = .FromArray(camera.mRayScale), .Offset = .FromArray(camera.mRayOffset) };

    var entered: std.ArrayList(u32) = .empty;
    try entered.ensureTotalCapacity(allocator, 512);

    //every pixel's ray, and the worst ones
    const Worst = struct { X: u32, Y: u32, Traced: Traced };
    var worst: [12]Worst = undefined;
    var worst_count: usize = 0;
    var totals = Replay.Walked{};
    var walks: u64 = 0;
    var rays: u64 = 0;
    //the rays ending in the front layer (a menu, a popup) against the rest: how many there are and what they cost
    var front = struct { Rays: u64 = 0, NodeTests: u64 = 0, Walks: u64 = 0 }{};
    const front_z = FrontLayerZ(dump.Shapes);
    const width: u32 = @intFromFloat(camera.mViewportWidth);
    const height: u32 = @intFromFloat(camera.mViewportHeight);
    var y: u32 = 0;
    while (y < height) : (y += PIXEL_STEP) {
        var x: u32 = 0;
        while (x < width) : (x += PIXEL_STEP) {
            const traced = Trace(replay, MakePixelRay(pose, params, x, y), &entered);
            rays += 1;
            walks += traced.WalkCount;
            totals.NodeTests += traced.Total.NodeTests;
            totals.ShapeTests += traced.Total.ShapeTests;
            for (std.enums.values(Visit)) |why| totals.Why.getPtr(why).* += traced.Total.Why.get(why);
            if (traced.FirstShape) |first| {
                if (ShapeZ(dump.Shapes[first]) >= front_z) {
                    front.Rays += 1;
                    front.NodeTests += traced.Total.NodeTests;
                    front.Walks += traced.WalkCount;
                }
            }

            //kept worst first
            const cost = traced.Total.NodeTests;
            if (worst_count < worst.len or cost > worst[worst_count - 1].Traced.Total.NodeTests) {
                var at = @min(worst_count, worst.len - 1);
                while (at > 0 and worst[at - 1].Traced.Total.NodeTests < cost) : (at -= 1) worst[at] = worst[at - 1];
                worst[at] = .{ .X = x, .Y = y, .Traced = traced };
                worst_count = @min(worst_count + 1, worst.len);
            }
        }
    }

    const print = std.debug.print;
    print("\n==== BVH dump replay: {d}x{d}, {d} shapes ({d} direct), {d} nodes, every {d}th pixel ====\n", .{ width, height, dump.Shapes.len, camera.mDirectCount, nodes.len, PIXEL_STEP });
    const per_ray = @as(f64, @floatFromInt(rays));
    print("average a pixel: {d:.2} walks, {d:.1} node tests, {d:.1} shape tests\n", .{ @as(f64, @floatFromInt(walks)) / per_ray, @as(f64, @floatFromInt(totals.NodeTests)) / per_ray, @as(f64, @floatFromInt(totals.ShapeTests)) / per_ray });
    for (std.enums.values(Visit)) |why| print("  {t}: {d:.1} a pixel\n", .{ why, @as(f64, @floatFromInt(totals.Why.get(why))) / per_ray });
    if (front.Rays > 0) {
        const front_rays = @as(f64, @floatFromInt(front.Rays));
        print("pixels whose first hit is in the front layer (z >= {d:.3}): {d}, {d:.2} walks and {d:.1} node tests each\n", .{ front_z, front.Rays, @as(f64, @floatFromInt(front.Walks)) / front_rays, @as(f64, @floatFromInt(front.NodeTests)) / front_rays });
    }

    print("worst pixels:\n", .{});
    for (worst[0..worst_count]) |w| {
        print("  ({d},{d}): {d} walks, {d} node tests, {d} shape tests", .{ w.X, w.Y, w.Traced.WalkCount, w.Traced.Total.NodeTests, w.Traced.Total.ShapeTests });
        for (std.enums.values(Visit)) |why| print(", {t} {d}", .{ why, w.Traced.Total.Why.get(why) });
        print("\n", .{});
    }

    //the worst pixel walk by walk: where each starts and ends, and what it cost
    if (worst_count > 0) {
        const w = worst[0];
        print("the worst pixel ({d},{d}), walk by walk:\n", .{ w.X, w.Y });
        for (w.Traced.Walks[0..w.Traced.WalkCount], 0..) |walk, walk_ind| {
            const ends_on = if (walk.FinalShape) |s| dump.Shapes[s] else null;
            print("  walk {d}: {d} node tests ({d} gone into, {d} needed), {d} shape tests, ends on {s}{s} at z {d:.4}\n", .{
                walk_ind,
                walk.NodeTests,
                walk.NodeTests - walk.Why.get(.Skipped),
                walk.Why.get(.Needed),
                walk.ShapeTests,
                if (ends_on) |s| @tagName(s.Type) else "nothing",
                if (ends_on) |s| (if (s.Flags & ShapeData.FLAG_TRANSPARENT != 0) " (see-through)" else "") else "",
                if (ends_on) |s| ShapeZ(s) else 0,
            });
        }
    }
}

/// How far down the camera's view a shape's center is: its world z, the camera looking down -z
fn ShapeZ(shape: ShapeData) f32 {
    return -(shape.AxisX[3] * shape.AxisX[2] + shape.AxisY[3] * shape.AxisY[2] + shape.AxisZ[3] * shape.AxisZ[2]);
}

/// Where the front layer starts: half way across the biggest gap in depth among the shapes, the popups' layer sitting
/// well in front of the rest
fn FrontLayerZ(shapes: []const ShapeData) f32 {
    var front = -std.math.inf(f32);
    for (shapes) |shape| front = @max(front, ShapeZ(shape));
    var cut = front;
    var gap: f32 = 0;
    for (shapes) |shape| {
        const z = ShapeZ(shape);
        //the nearest shape behind z, to see how big a gap there is in front of it
        var next = front;
        for (shapes) |other| {
            const other_z = ShapeZ(other);
            if (other_z > z and other_z < next) next = other_z;
        }
        if (next - z > gap) {
            gap = next - z;
            cut = z + gap / 2;
        }
    }
    return cut;
}

fn MakePixelRay(pose: CameraRay.Pose, params: CameraRay.RayParams, x: u32, y: u32) Ray {
    return CameraRay.MakeRay(pose, params, .{ .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5 });
}

/// One pixel's ray with every walk it takes: on through each see-through shape it ends on, from where it hit it and
/// skipping it, the way SDFRayMarcher.March starts a new edge, up to its MAX_EDGES
const Traced = struct {
    Walks: [MAX_EDGES]Replay.Walked = undefined,
    WalkCount: u32 = 0,
    Total: Replay.Walked = .{},
    FirstShape: ?u32 = null,
};

/// SDFRayMarcher.MAX_EDGES
const MAX_EDGES = 8;

fn Trace(replay: Replay, first_ray: Ray, entered: *std.ArrayList(u32)) Traced {
    var traced = Traced{};
    var ray = first_ray;
    var skip: ?u32 = null;
    while (traced.WalkCount < MAX_EDGES) {
        const walked = replay.Walk(ray, skip, entered);
        traced.Walks[traced.WalkCount] = walked;
        traced.WalkCount += 1;
        traced.Total.NodeTests += walked.NodeTests;
        traced.Total.ShapeTests += walked.ShapeTests;
        for (std.enums.values(Visit)) |why| traced.Total.Why.getPtr(why).* += walked.Why.get(why);
        const shape_ind = walked.FinalShape orelse break;
        if (traced.FirstShape == null) traced.FirstShape = shape_ind;
        if (replay.Dump.Shapes[shape_ind].Flags & ShapeData.FLAG_TRANSPARENT == 0) break;
        ray.Origin = ray.Origin.AddVec(ray.Dir.MulScalar(walked.FinalT));
        skip = shape_ind;
    }
    return traced;
}
