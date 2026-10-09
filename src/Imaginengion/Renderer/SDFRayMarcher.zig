const std = @import("std");
const ShapeData = @import("Renderer2D.zig").ShapeData;
const ShapeSurface = @import("Renderer2D.zig").ShapeSurface;

const MathTypes = @import("../Math/MathTypes.zig");
const Ray = @import("../Math/CameraRay.zig").Ray;
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const SDFFunc = @import("../Math/SDFFunctions.zig");
const RayIntersect = @import("../Math/RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;
const BVH = @import("../Core/BVH.zig");
const BVHNode = BVH.Node;
const SDFProgram = @import("SDFProgram.zig");

const ShapeType = @import("Renderer.zig").ShapeType;

const THICKNESS_2D = SDFFunc.THICKNESS_2D;

const Stack = @import("../Core/Stack.zig").Stack;

//A ray that runs out of steps is treated as a miss, so this is a budget rather than a safety net:
//every step costs one SDF evaluation against every marched shape, for every pixel. At 9999 a
//single grazing band of pixels was enough to push one dispatch into the seconds and trip the
//driver's watchdog. With a distance-scaled hit threshold (see SurfaceEpsilon) rays converge in
//far fewer steps than this, so the budget is only reached by rays that were going to miss.
const MAX_STEPS: u32 = 256;

//How many hits the direct search turns down along one edge before it gives up and counts the edge as a miss. A hit is
//turned down when its masks cut it off or it is in a gap in a letter, and each one costs another pass over every
//direct shape, so this keeps a pixel looking through a long run of letter gaps from looping. Text is the usual
//case: a ray between letters passes through the edges of a few overlapping glyph boxes, well under this
pub const MAX_DIRECT_REJECTS: u32 = 16;

//The hit threshold at the camera. SurfaceEpsilon grows it with distance; this is the t = 0 value.
const SURF_DIST: f32 = 0.00099;

/// How close a ray has to get to a surface before it counts as a hit.
///
/// This grows with how far the ray has already travelled, because a pixel covers more world space
/// the further out you look. Held constant, the threshold asks a distant ray to resolve detail far
/// smaller than the pixel it is shading: it can never get there, so it creeps forward a fraction of
/// a unit per step until the budget runs out. That is what let one off-centre quad hang the GPU,
/// since rays grazing past a 0.002-thick plate stay just outside a constant threshold for hundreds
/// of units of travel.
///
/// max(1, t) keeps close-up geometry at full precision and only relaxes the threshold once the ray
/// is far enough out that the extra precision is smaller than a pixel. A truer version would take
/// the camera's actual per-pixel cone angle rather than assuming one, which would need the ray
/// footprint passing through from the camera UBO.
fn SurfaceEpsilon(dist_origin: f32) f32 {
    return SURF_DIST * @max(1.0, dist_origin);
}

pub const MAX_NODES: u32 = 9;
pub const MAX_EDGES: u32 = 8;
const SKY_COLOR: Vec3(f32) = .{ .x = 0.53, .y = 0.81, .z = 0.92 }; //FOR SIMULATING

//NOTE: This represents a surface that we hit
pub const Node = extern struct {
    AccumColor: Vec4(f32),
    Point: Vec3(f32),
    Normal: Vec3(f32),
    TextureUV: Vec3(f32),
    ParentEdge: u32,
    FirstEdge: u32,
    MaterialHandle: u32,
    ShapeT: ShapeType,
};

//NOTE: This represents travelling through volume
pub const Edge = extern struct {
    AccumColor: Vec4(f32),
    Direction: Vec3(f32),
    Length: f32,
    FromNode: u32,
    ToNode: u32,
    SiblingEdge: u32,
    //the medium it travels through, into the medium shadings. 0 is air, the only one there is so far
    MaterialHandle: u32,
    //the shape this edge starts on, which the search ignores. A continuation edge starts within
    //epsilon of the plate it passed through, so without this it immediately re-hits that same plate
    //and spawns another edge, forever. Every shape is a flat plate, so a straight ray can't
    //legitimately hit the one it just left.
    SkipShape: u32 = NO_SHAPE,
};

/// A shape index that is no shape: what a miss or an empty skip slot holds
const NO_SHAPE: u32 = std.math.maxInt(u32);

/// A hit the march has checked against the shape itself.
const SurfaceHit = struct {
    Found: bool,
    //the shape's index in the shape buffer, and its kind
    Shape: u32,
    Type: ShapeType,
    T: f32,
    Normal: Vec3(f32),
    TextureUV: Vec3(f32),
    //which surface the hit is shaded with: usually the shape's own, but a quad's border band has its own. OWN_COLOR for
    //a merge, whose color at the hit is Color
    ShadingHandle: u32,
    Color: Vec4(f32) = .{ .x = 0, .y = 0, .z = 0, .w = 0 },

    const none: SurfaceHit = .{
        .Found = false,
        .Shape = NO_SHAPE,
        .Type = .None,
        .T = 0,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
        .ShadingHandle = 0,
    };
};

/// Only a plate's front is drawn. Its back or thin sides, or a ray starting inside it, is nothing there.
fn IsFrontHit(hit: HitInfo) bool {
    if (!hit.IsHit() or hit.StartedInside) return false;
    const face = hit.Face orelse return false;
    return face == .PosZ;
}

/// The ray straight against a shape, by its kind
fn HitShape(ray: Ray, shape: ShapeData) HitInfo {
    return switch (shape.Type) {
        .Quad => SDFFunc.rayIMQuad(ray, shape),
        .Glyph => SDFFunc.rayIMGlyph(ray, shape),
        .Merge => SDFFunc.rayIMMerge(ray, shape),
        .None => .miss,
    };
}

/// Which kind of shape wins an exact tie: a quad, then a merge, then a glyph, so text on either stays on top
fn TieRank(shape_type: ShapeType) u32 {
    return switch (shape_type) {
        .Quad => 0,
        .Merge => 1,
        .Glyph => 2,
        .None => 3,
    };
}

/// A node's MaterialHandle when its surface color was worked out at the hit and is already in its AccumColor: a merge,
/// whose color comes from its program, not a surface shading
const OWN_COLOR: u32 = std.math.maxInt(u32);

/// Where a hit comes along a ray, which settles exact ties too: nearer first, then a quad before a glyph, then the
/// one drawn first. Draw order is each shape's SurfaceIndex, since surfaces are added in the order shapes are drawn
/// and are never reordered, where the shapes are (sorted for the BVH)
const HitOrder = struct {
    T: f32,
    Rank: u32,
    DrawOrder: u32,
    //the shape's place in the shape buffer, which isn't compared: what the search hands back
    Shape: u32,

    /// Before every hit, where the direct search starts from
    const start: HitOrder = .{ .T = -std.math.inf(f32), .Rank = 0, .DrawOrder = 0, .Shape = 0 };

    fn Of(t: f32, shape: ShapeData, shape_ind: u32) HitOrder {
        return .{ .T = t, .Rank = TieRank(shape.Type), .DrawOrder = shape.SurfaceIndex, .Shape = shape_ind };
    }

    fn Before(self: HitOrder, other: HitOrder) bool {
        if (self.T != other.T) return self.T < other.T;
        if (self.Rank != other.Rank) return self.Rank < other.Rank;
        return self.DrawOrder < other.DrawOrder;
    }
};

const MAX_SKIPS: u32 = 4;

/// What one edge's march ignores: the shape the edge starts on, and any the march has come within
/// epsilon of and SurfaceAt turned down. A straight ray can't come back round to a flat plate it has
/// passed, so a turned down shape stays skipped for the rest of the edge, which also stops the march
/// sitting on it. When it's full the oldest goes, the one furthest behind the ray. Skipping is only to
/// get past things: a shape that drops out and gets touched again is just turned down again.
const SkipList = struct {
    mShapes: [MAX_SKIPS]u32,
    mNext: u32,

    fn Init(first: u32) SkipList {
        var list = SkipList{
            .mShapes = @splat(NO_SHAPE),
            .mNext = 1,
        };
        list.mShapes[0] = first;
        return list;
    }

    fn Add(self: *SkipList, shape: u32) void {
        self.mShapes[self.mNext] = shape;
        self.mNext = (self.mNext + 1) % MAX_SKIPS;
    }

    fn Contains(self: SkipList, shape: u32) bool {
        for (self.mShapes) |skipped| {
            if (skipped == shape) return true;
        }
        return false;
    }
};

const NodeArr = [MAX_NODES]Node;
const EdgeArr = [MAX_EDGES]Edge;

const MarchData = extern struct {
    min_dist: f32,
    shape: u32,
};

/// How the direct search finds which shapes to ray test, picked when the marcher is compiled. Everything else about
/// the search is the same either way (DirectSurface, ConsiderShape), so the two differ only in NearestByBVH and
/// NearestByLinearSearch
pub const DirectSearch = enum {
    /// Walks the BVH over the direct shapes, testing only the shapes in leaves the ray reaches. What the shaders use
    BVH,
    /// Tests every direct shape. Kept as the answer key the BVH walk is tested against, and as a way to rule the
    /// tree out when hunting a rendering bug. Never compiled into the shaders
    Linear,
};

/// How far a BVH node's box can reach past what it was built around and still count, as a share of the distance
/// along the ray (at least 1 unit's worth). A box is worked out on the CPU from a shape's axes and a hit on the GPU
/// in the shape's own space, so for a plate facing the ray the box's face and the plate's are the same distance away
/// up to rounding. Without this a box could round to just past a hit it holds and be pruned, losing an exact tie
const BVH_BOX_SLACK: f32 = 0.0001;

pub fn RayMarcher(comptime shapes_type: type, comptime shape_surfaces_type: type, comptime bvh_nodes_type: type, comptime masks_type: type, comptime instrs_type: type, comptime parts_type: type, comptime surf_shading_type: type, comptime med_shading_type: type, comptime textures_array_type: type, comptime direct_search: DirectSearch) type {
    return extern struct {
        pub const NO_EDGE: u32 = std.math.maxInt(u32);
        const Self = @This();

        /// the ray tree, filled from Start on
        mNodes: NodeArr = undefined,
        mEdges: EdgeArr = undefined,
        mNodeCount: usize = 0,
        mEdgeCount: usize = 0,
        mDefaultColor: Vec4(f32),
        /// every shape a ray looks for, every kind in one buffer (ShapeData), and what only a hit one needs
        /// (ShapeSurface), by each shape's SurfaceIndex
        mShapes: shapes_type,
        mShapeSurfaces: shape_surfaces_type,
        mShapesCount: usize,
        /// the shapes are sorted direct first (ShapeSort): [0, mDirectCount) are found with a ray test straight
        /// against each, the rest by marching
        mDirectCount: usize,
        /// the BVH over the direct shapes (Core/BVH.zig), its leaves' items their place in mShapes. The root's Skip is
        /// the node count, and there are no nodes when mDirectCount is 0
        mBVHNodes: bvh_nodes_type,
        /// the masks shapes are cut by, by their MaskIndex, and the programs of the masks' shapes (SDFProgram)
        mMasks: masks_type,
        mInstrs: instrs_type,
        mParts: parts_type,
        mSurfShading: surf_shading_type,
        mMedShading: med_shading_type,
        mPerspectiveFar: f32,

        /// Plants the ray tree's root for `ray`: the node it starts from and the edge it sets out along, through air.
        /// Every trace starts here, then March, then GenerateColor
        pub fn Start(self: *Self, ray: Ray) void {
            self.mNodes[0] = .{
                .Point = ray.Origin,
                .Normal = .{ .x = 0, .y = 0, .z = 0 },
                .ParentEdge = NO_EDGE,
                .FirstEdge = 0,
                .MaterialHandle = 0,
                .AccumColor = self.mDefaultColor,
                .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
                .ShapeT = .None,
            };
            self.mEdges[0] = .{
                .Direction = ray.Dir,
                .Length = 0.0,
                .FromNode = 0,
                .ToNode = 0,
                .SiblingEdge = NO_EDGE,
                .AccumColor = self.mDefaultColor,
                .MaterialHandle = 0,
            };
            self.mNodeCount = 1;
            self.mEdgeCount = 1;
        }

        pub fn March(self: *Self, sample_sampler: anytype, textures_array: textures_array_type) void {
            var edge_ind_stack: Stack(usize, MAX_EDGES) = .empty;
            edge_ind_stack.Push(0);

            while (edge_ind_stack.len > 0) {
                const curr_edge_ind = edge_ind_stack.Pop();
                const curr_edge = self.mEdges[curr_edge_ind];
                const from_point = self.mNodes[@intCast(curr_edge.FromNode)].Point;

                const edge_ray = Ray{ .Origin = from_point, .Dir = curr_edge.Direction };

                //the direct shapes first, then the marched ones only as far as that hit, since nothing behind it
                //can show. With no marched shapes, every pixel skips the march together
                var surface = self.DirectSurface(edge_ray, curr_edge.SkipShape, sample_sampler, textures_array);
                if (self.mDirectCount < self.mShapesCount) {
                    const limit = if (surface.Found) surface.T else self.mPerspectiveFar;
                    const marched = self.MarchedSurface(edge_ray, curr_edge.SkipShape, limit, sample_sampler, textures_array);
                    if (marched.Found and marched.T < limit) surface = marched;
                }

                //nothing drawn along it before the far distance, the ray dies
                if (!surface.Found) {
                    self.mEdges[curr_edge_ind].Length = self.mPerspectiveFar;
                    const miss_node_ind = self.GetNodeIndex();
                    self.mNodes[miss_node_ind] = .{
                        .Point = from_point.AddVec(curr_edge.Direction.MulScalar(self.mPerspectiveFar)),
                        .Normal = .{ .x = 0, .y = 0, .z = 0 },
                        .ParentEdge = @intCast(curr_edge_ind),
                        .FirstEdge = NO_EDGE,
                        .MaterialHandle = 0,
                        .AccumColor = self.mDefaultColor,
                        .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
                        .ShapeT = .None,
                    };
                    self.mEdges[curr_edge_ind].ToNode = @intCast(miss_node_ind);
                    continue;
                }

                //the exact point on the surface, rather than wherever within epsilon a march stopped
                self.mEdges[curr_edge_ind].Length = surface.T;
                const end_point = from_point.AddVec(curr_edge.Direction.MulScalar(surface.T));
                const shading_handle = surface.ShadingHandle;

                const new_node_ind = self.GetNodeIndex();
                self.mNodes[new_node_ind] = Node{
                    .Point = end_point,
                    .Normal = surface.Normal,
                    .ParentEdge = @intCast(curr_edge_ind),
                    .FirstEdge = NO_EDGE,
                    .MaterialHandle = shading_handle,
                    .AccumColor = if (shading_handle == OWN_COLOR) surface.Color else self.mDefaultColor,
                    .TextureUV = surface.TextureUV,
                    .ShapeT = surface.Type,
                };

                self.mEdges[curr_edge_ind].ToNode = @intCast(new_node_ind);

                //now for checking if we need to spawn more edges based off different material properties of the object
                //in the future can expand this to do reflectivity, lighting, shadows, refraction, whatever else exists idk
                const shading_flags = self.mShapes[surface.Shape].Flags;

                //if transparent bit is set, aka it can be some level of transparent and we are not already full of edges.
                //mEdgeCount is the real bound: the stack is popped before each push so it never fills, and
                //each edge adds exactly one node, so this also keeps mNodeCount <= MAX_NODES
                if (shading_flags & ShapeData.FLAG_TRANSPARENT != 0 and self.mEdgeCount < MAX_EDGES and !edge_ind_stack.IsFull()) {
                    const alpha = self.SurfaceColor(self.mNodes[new_node_ind], sample_sampler, textures_array).w;
                    if (alpha < 1.0) {
                        const new_edge_ind = self.GetEdgeIndex();

                        self.mEdges[new_edge_ind] = Edge{
                            .Direction = curr_edge.Direction,
                            .Length = 0,
                            .FromNode = @intCast(new_node_ind),
                            .ToNode = 0,
                            .SiblingEdge = NO_EDGE,
                            .AccumColor = self.mDefaultColor,
                            .MaterialHandle = 0,
                            .SkipShape = surface.Shape,
                        };

                        self.mNodes[new_node_ind].FirstEdge = @intCast(new_edge_ind);
                        edge_ind_stack.Push(new_edge_ind);
                    }
                }
            }
        }

        pub fn GenerateColor(self: *Self, sample_sampler: anytype, textures_array: textures_array_type) Vec4(f32) {
            var i: usize = self.mNodeCount;
            while (i > 0) {
                i -= 1;
                const node = self.mNodes[i];

                var ei: u32 = node.FirstEdge;
                while (ei != NO_EDGE) {
                    self.CalcEdgeColor(ei);
                    ei = self.mEdges[@intCast(ei)].SiblingEdge;
                }
                self.CalcNodeColor(i, sample_sampler, textures_array);
            }

            return self.mNodes[0].AccumColor;
        }

        fn GetNodeIndex(self: *Self) usize {
            defer self.mNodeCount += 1;
            return self.mNodeCount;
        }

        fn GetEdgeIndex(self: *Self) usize {
            defer self.mEdgeCount += 1;
            return self.mEdgeCount;
        }

        /// The nearest surface a ray draws among the direct shapes, by a ray test straight against each candidate
        /// (picked by `direct_search`). The nearest hit is then checked against the shape itself (SurfaceFromHit), and
        /// one turned down, cut off by its masks or in a gap in a letter, is passed for the next one after it, up to
        /// MAX_DIRECT_REJECTS of them
        fn DirectSurface(self: *const Self, ray: Ray, skip_shape: u32, sample_sampler: anytype, textures_array: textures_array_type) SurfaceHit {
            if (self.mDirectCount == 0) return .none;
            var after = HitOrder.start;
            var searches: u32 = 0;
            while (searches <= MAX_DIRECT_REJECTS) : (searches += 1) {
                const nearest = switch (direct_search) {
                    .BVH => self.NearestByBVH(ray, skip_shape, after),
                    .Linear => self.NearestByLinearSearch(ray, skip_shape, after),
                };
                if (nearest.Order.Shape == NO_SHAPE) return .none;
                const surface = self.SurfaceFromHit(ray, nearest.Order.Shape, nearest.Hit, sample_sampler, textures_array);
                if (surface.Found) return surface;
                after = nearest.Order;
            }
            return .none;
        }

        /// The nearest direct hit a search has found so far, and the hit itself for SurfaceFromHit
        const Candidate = struct {
            Order: HitOrder,
            Hit: HitInfo,
        };

        /// Nothing found yet: anything nearer than the far distance beats it
        fn NoCandidate(self: *const Self) Candidate {
            return .{
                .Order = .{ .T = self.mPerspectiveFar, .Rank = std.math.maxInt(u32), .DrawOrder = std.math.maxInt(u32), .Shape = NO_SHAPE },
                .Hit = .miss,
            };
        }

        /// Ray tests one direct shape, and makes it the nearest if its front is hit after `after` and before the
        /// nearest so far. All a search does with a shape, whichever way it found it
        fn ConsiderShape(self: *const Self, ray: Ray, shape_ind: u32, skip_shape: u32, after: HitOrder, nearest: *Candidate) void {
            if (shape_ind == skip_shape) return;
            const shape: ShapeData = self.mShapes[shape_ind];
            const hit = HitShape(ray, shape);
            if (!IsFrontHit(hit)) return;
            const order = HitOrder.Of(hit.T, shape, shape_ind);
            if (after.Before(order) and order.Before(nearest.Order)) nearest.* = .{ .Order = order, .Hit = hit };
        }

        //==================================the two direct searches (DirectSearch)==================================

        /// DirectSearch.BVH: walks the tree over the direct shapes the stack free way (Core/BVH.zig), into each node the
        /// ray reaches and on to its Skip past each it doesn't, considering the shapes of every leaf it reaches. A leaf's
        /// shapes are a run of mShapes, since the tree was built over them in that order
        fn NearestByBVH(self: *const Self, ray: Ray, skip_shape: u32, after: HitOrder) Candidate {
            var nearest = self.NoCandidate();
            const inv_dir = Vec3(f32).FromVector(@as(Vec3(f32).VectorT, @splat(1.0)) / ray.Dir.ToVector());
            const node_count = self.mBVHNodes[0].Skip;
            var node_ind: u32 = 0;
            while (node_ind < node_count) {
                const node: BVHNode = self.mBVHNodes[node_ind];
                if (!ReachesNode(ray, inv_dir, node, after, nearest.Order)) {
                    node_ind = node.Skip;
                    continue;
                }
                if (!node.IsLeaf()) {
                    node_ind += 1;
                    continue;
                }
                const first = node.FirstItem();
                for (first..first + node.ItemCount()) |shape_ind| self.ConsiderShape(ray, @intCast(shape_ind), skip_shape, after, &nearest);
                node_ind = node.Skip;
            }
            return nearest;
        }

        /// DirectSearch.Linear: considers every direct shape, the BVH walk's answer key
        fn NearestByLinearSearch(self: *const Self, ray: Ray, skip_shape: u32, after: HitOrder) Candidate {
            var nearest = self.NoCandidate();
            for (0..self.mDirectCount) |shape_ind| self.ConsiderShape(ray, @intCast(shape_ind), skip_shape, after, &nearest);
            return nearest;
        }

        /// Whether a BVH walk goes into `node`: it holds shapes to draw, the ray goes through its box, and the box
        /// could hold a hit between `after` (the last one turned down) and `nearest`. A box starting past the nearest
        /// hit so far can't hold anything nearer, and one ending before the turned down hit was all passed already.
        /// Both are let off by BVH_BOX_SLACK, and an exact equal is kept, so a tie at the same distance still gets looked at
        fn ReachesNode(ray: Ray, inv_dir: Vec3(f32), node: BVHNode, after: HitOrder, nearest: HitOrder) bool {
            if (node.ItemMask() & BVH.Mask.RENDER == 0) return false;
            const bounds = node.Bounds();
            const span = RayIntersect.RayAabb(ray.Origin, inv_dir, bounds.Min, bounds.Max) orelse return false;
            const slack = BVH_BOX_SLACK * @max(1.0, @abs(nearest.T));
            return span.Enter <= nearest.T + slack and span.Exit >= after.T - slack;
        }

        /// The nearest surface a ray draws among the marched shapes, stepping along it no further than `limit`. Each
        /// shape the march gets within epsilon of is checked against the shape itself, and one turned down is skipped
        /// for the rest of the edge (SkipList)
        fn MarchedSurface(self: *const Self, ray: Ray, skip_shape: u32, limit: f32, sample_sampler: anytype, textures_array: textures_array_type) SurfaceHit {
            var skips = SkipList.Init(skip_shape);
            var dist_origin: f32 = 0;

            var i: u32 = 0;
            while (i < MAX_STEPS and dist_origin < limit) : (i += 1) {
                const point = ray.Origin.AddVec(ray.Dir.MulScalar(dist_origin));
                const march_data = self.NextSurface(point, skips);
                if (march_data.min_dist > SurfaceEpsilon(dist_origin)) {
                    dist_origin += march_data.min_dist;
                    continue;
                }

                //close enough to count, so ask the shape itself where exactly the ray meets it. only
                //a plate's front is drawn, and a glyph only where the letter covers it: at its back,
                //its sides or a gap in the letter the ray goes on to whatever is behind
                const surface = self.SurfaceAt(ray, march_data.shape, sample_sampler, textures_array);
                if (surface.Found) return surface;
                skips.Add(march_data.shape);
            }
            return .none;
        }

        /// The nearest marched shape to `point`, cut by its masks
        fn NextSurface(self: *const Self, point: Vec3(f32), skips: SkipList) MarchData {
            var data = MarchData{ .min_dist = self.mPerspectiveFar, .shape = NO_SHAPE };
            var nearest_rank: u32 = std.math.maxInt(u32);
            var nearest_draw_order: u32 = std.math.maxInt(u32);

            for (self.mDirectCount..self.mShapesCount) |i| {
                const shape_ind: u32 = @intCast(i);
                if (skips.Contains(shape_ind)) continue;
                const shape: ShapeData = self.mShapes[i];
                const shape_dist = switch (shape.Type) {
                    .Quad => SDFFunc.sdIMQuad(point, shape),
                    .Glyph => SDFFunc.sdIMGlyph(point, shape),
                    .Merge => SDFProgram.sdIMMerge(point, shape, self.mInstrs, self.mParts),
                    .None => continue,
                };
                const dist = SDFProgram.Masked(self.mMasks, self.mInstrs, self.mParts, shape.MaskIndex, shape_dist, point);
                //an exact tie goes the way HitOrder settles one: a quad before a glyph, then the one drawn first
                const rank = TieRank(shape.Type);
                const wins_tie = dist == data.min_dist and
                    (rank < nearest_rank or (rank == nearest_rank and shape.SurfaceIndex < nearest_draw_order));
                if (dist < data.min_dist or wins_tie) {
                    data.min_dist = dist;
                    data.shape = shape_ind;
                    nearest_rank = rank;
                    nearest_draw_order = shape.SurfaceIndex;
                }
            }
            return data;
        }

        /// Whether a hit on a shape is kept by its masks. One cut off isn't drawn, and the ray goes on to whatever is
        /// behind, the same as through a gap in a letter
        fn InMasks(self: *const Self, point: Vec3(f32), mask_ind: u32) bool {
            return SDFProgram.InMasks(self.mMasks, self.mInstrs, self.mParts, mask_ind, point);
        }

        /// Where the ray meets shape `shape_ind`, if it does in a way that's drawn: the front of a plate, and for
        /// a glyph, only where the letter covers it. Neither where its masks cut it off
        fn SurfaceAt(self: *const Self, ray: Ray, shape_ind: u32, sample_sampler: anytype, textures_array: textures_array_type) SurfaceHit {
            return self.SurfaceFromHit(ray, shape_ind, HitShape(ray, self.mShapes[shape_ind]), sample_sampler, textures_array);
        }

        /// SurfaceAt for a hit already found against the shape (HitShape), so the direct search doesn't test the ray
        /// against it twice
        fn SurfaceFromHit(self: *const Self, ray: Ray, shape_ind: u32, hit: HitInfo, sample_sampler: anytype, textures_array: textures_array_type) SurfaceHit {
            if (!IsFrontHit(hit)) return .none;
            const shape: ShapeData = self.mShapes[shape_ind];
            const surface: ShapeSurface = self.mShapeSurfaces[shape.SurfaceIndex];
            switch (shape.Type) {
                .Quad => {
                    const hit_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
                    if (!self.InMasks(hit_point, shape.MaskIndex)) return .none;

                    //the band around the edge is the border's solid color, the rest is the quad's own surface
                    if (SDFFunc.InIMQuadBorder(hit_point, shape, surface.BorderWidth)) {
                        return .{
                            .Found = true,
                            .Shape = shape_ind,
                            .Type = shape.Type,
                            .T = hit.T,
                            .Normal = hit.Normal,
                            .TextureUV = SDFFunc.UNTEXTURED_UV,
                            .ShadingHandle = surface.BorderShadingHandle,
                        };
                    }

                    const texture_shading_data = self.mSurfShading[surface.ShadingHandle];
                    return .{
                        .Found = true,
                        .Shape = shape_ind,
                        .Type = shape.Type,
                        .T = hit.T,
                        .Normal = hit.Normal,
                        .TextureUV = SDFFunc.TextureUV(
                            texture_shading_data.Texturehandle,
                            hit.UV,
                            texture_shading_data.TextureWidth,
                            texture_shading_data.TextureHeight,
                        ),
                        .ShadingHandle = surface.ShadingHandle,
                    };
                },
                .Glyph => {
                    if (!self.InMasks(ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)), shape.MaskIndex)) return .none;

                    //the coverage test needs where in the glyph's box the hit is. the fill texture's UV
                    //is a different thing, a spot in its texture manager slot, and only for color
                    const atlas_shading_data = self.mSurfShading[surface.ShadingHandle];
                    if (SDFFunc.GetMSD(hit.UV, atlas_shading_data, textures_array, sample_sampler) < 0.5) return .none;

                    //the atlas only says where the letter is. What it is painted with, the text's color and texture, is
                    //the fill surface the atlas entry points on to, so that is what the hit is shaded with
                    const fill_handle = atlas_shading_data.SiblingShading;
                    const texture_shading_data = self.mSurfShading[fill_handle];
                    return .{
                        .Found = true,
                        .Shape = shape_ind,
                        .Type = shape.Type,
                        .T = hit.T,
                        .Normal = hit.Normal,
                        .TextureUV = SDFFunc.TextureUV(
                            texture_shading_data.Texturehandle,
                            hit.UV,
                            texture_shading_data.TextureWidth,
                            texture_shading_data.TextureHeight,
                        ),
                        .ShadingHandle = fill_handle,
                    };
                },
                .Merge => {
                    const hit_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
                    if (!self.InMasks(hit_point, shape.MaskIndex)) return .none;

                    //the box only says where it could be: the program says whether it is there, the way a letter's
                    //coverage does for a glyph
                    const value = SDFProgram.Eval(self.mInstrs, self.mParts, SDFProgram.MergeRange(shape), hit_point, PartShader(sample_sampler){}, self.mSurfShading, textures_array);
                    if (value.D > 0) return .none;

                    //the band around the whole merged outline is the border's solid color
                    if (surface.BorderWidth > 0 and value.D > -surface.BorderWidth) {
                        return .{
                            .Found = true,
                            .Shape = shape_ind,
                            .Type = shape.Type,
                            .T = hit.T,
                            .Normal = hit.Normal,
                            .TextureUV = SDFFunc.UNTEXTURED_UV,
                            .ShadingHandle = surface.BorderShadingHandle,
                        };
                    }
                    return .{
                        .Found = true,
                        .Shape = shape_ind,
                        .Type = shape.Type,
                        .T = hit.T,
                        .Normal = hit.Normal,
                        .TextureUV = SDFFunc.UNTEXTURED_UV,
                        .ShadingHandle = OWN_COLOR,
                        .Color = value.Color,
                    };
                },
                .None => return .none,
            }
        }

        /// The colorer a merge's hit is shaded with (SDFProgram.Eval), given the surface shadings and the textures: each
        /// part painted at the hit the way a quad's surface is, its texture at its own UV tinted by its color
        fn PartShader(comptime sample_sampler: anytype) type {
            return struct {
                pub fn Color(_: @This(), _: u32, part: SDFProgram.Part, point: Vec3(f32), shadings: surf_shading_type, textures: textures_array_type) Vec4(f32) {
                    const shading = shadings[part.Shading];
                    const texture_uv = SDFFunc.TextureUV(shading.Texturehandle, SDFProgram.PartUV(part, point), shading.TextureWidth, shading.TextureHeight);
                    return Vec4(f32).FromVector(shading.Color).MulVec(SampleTexture(texture_uv, sample_sampler, textures));
                }
            };
        }

        fn CalcNodeColor(self: *Self, node_ind: usize, sample_sampler: anytype, textures_array: textures_array_type) void {
            const curr_node = self.mNodes[node_ind];

            const child_accum = if (curr_node.FirstEdge == NO_EDGE) self.mDefaultColor else self.mEdges[@intCast(curr_node.FirstEdge)].AccumColor;

            const color = self.SurfaceColor(curr_node, sample_sampler, textures_array);
            const alpha = color.w;

            self.mNodes[node_ind].AccumColor = color.Lerp(child_accum, 1.0 - alpha);
        }

        /// The color of the surface a node is on, before anything behind it shows through: its surface shading's
        /// color tinting its texture, or for a merge the color its program gave it at the hit
        fn SurfaceColor(self: *const Self, node: Node, sample_sampler: anytype, textures_array: textures_array_type) Vec4(f32) {
            if (node.MaterialHandle == OWN_COLOR) return node.AccumColor;
            const material = self.mSurfShading[node.MaterialHandle];
            const texture_color = SampleTexture(node.TextureUV, sample_sampler, textures_array);
            const material_color = Vec4(f32).FromVector(material.Color);
            return material_color.MulVec(texture_color); // tint
        }

        fn CalcEdgeColor(self: *Self, edge_ind: u32) void {
            const curr_edge = self.mEdges[edge_ind];
            const to_node = self.mNodes[curr_edge.ToNode];

            const child_accum = to_node.AccumColor;

            //the medium the edge travels through is its own. The node it leaves is a surface, and its MaterialHandle
            //is into the surface shadings, which say nothing about what is on the other side
            const material = self.mMedShading[curr_edge.MaterialHandle];

            // Beer-Lambert for absorbtion  over edge length
            const extinction = Vec3(f32).FromArray(material.Absorption).AddVec(.FromArray(material.Scattering));
            const transmittance = extinction.Neg().MulScalar(curr_edge.Length).Exp();

            //scattering
            const ONE = Vec3(f32){ .x = 1, .y = 1, .z = 1 };
            const scatter_amount = ONE.SubVec(Vec3(f32).FromArray(material.Scattering).Neg().MulScalar(curr_edge.Length).Exp());

            const transmitted = transmittance.MulVec(.{ .x = child_accum.x, .y = child_accum.y, .z = child_accum.z });
            const inscattered = scatter_amount.MulVec(SKY_COLOR);

            const color_out = transmitted.AddVec(inscattered);

            self.mEdges[edge_ind].AccumColor = .{ .x = color_out.x, .y = color_out.y, .z = color_out.z, .w = child_accum.w };
        }

        fn SampleTexture(texture_uv: Vec3(f32), sample_sampler: anytype, textures_array: textures_array_type) Vec4(f32) {
            //a solid color surface: the surface's color comes through as it is
            if (texture_uv.z == SDFFunc.UNTEXTURED_UV.z) return Vec4(f32){ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            if (texture_uv.x < 0 or texture_uv.y < 0 or texture_uv.z < 0) return Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };

            return .FromVector(sample_sampler(textures_array, texture_uv.ToVector(), 0.0));
        }
    };
}
