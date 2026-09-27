const std = @import("std");
const QuadData = @import("Renderer2D.zig").QuadData;
const GlyphData = @import("Renderer2D.zig").GlyphData;
const SurfShadingData = @import("Renderer.zig").SurfShadingData;
const MedShadingData = @import("Renderer.zig").MedShadingData;
const EShadingFlags = @import("Renderer.zig").EShadingFlags;

const MathTypes = @import("../Math/MathTypes.zig");
const Ray = @import("../Math/CameraRay.zig").Ray;
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const SDFFunc = @import("../Math/SDFFunctions.zig");
const HitInfo = @import("../Math/RayIntersect.zig").HitInfo;

const ShapeType = @import("Renderer.zig").ShapeType;

const THICKNESS_2D = SDFFunc.THICKNESS_2D;

const Stack = @import("../Core/Stack.zig").Stack;

//A ray that runs out of steps is treated as a miss, so this is a budget rather than a safety net:
//every step costs one SDF evaluation against every quad and glyph, for every pixel. At 9999 a
//single grazing band of pixels was enough to push one dispatch into the seconds and trip the
//driver's watchdog. With a distance-scaled hit threshold (see SurfaceEpsilon) rays converge in
//far fewer steps than this, so the budget is only reached by rays that were going to miss.
const MAX_STEPS: u32 = 256;

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
    MaterialHandle: u32,
    //the object this edge starts on, which the march ignores. A continuation edge starts within
    //epsilon of the plate it passed through, so without this it immediately re-hits that same plate
    //and spawns another edge, forever. Every shape is a flat plate, so a straight ray can't
    //legitimately hit the one it just left.
    SkipObject: ObjectData = .{ .shape_type = .None, .shape_ind = 0 },
};

const ObjectData = extern struct {
    shape_type: ShapeType,
    shape_ind: usize,

    pub fn Equals(self: ObjectData, other: ObjectData) bool {
        if (self.shape_type == other.shape_type and self.shape_ind == other.shape_ind) return true else false;
    }
    pub fn Is2D(self: ObjectData) bool {
        if (self.shape_type == ShapeType.Quad or self.shape_type == ShapeType.Glyph) return true;
        return false;
    }
    pub fn GetShadingHandle(self: ObjectData, quads: anytype, glyphs: anytype) u32 {
        return switch (self.shape_type) {
            .Quad => quads[self.shape_ind].ShadingHandle,
            .Glyph => glyphs[self.shape_ind].AtlasShadingHandle,
            else => 0,
        };
    }
    pub fn GetShadingFlags(self: ObjectData, quads: anytype, glyphs: anytype) u32 {
        return switch (self.shape_type) {
            .Quad => quads[self.shape_ind].ShadingFlags,
            .Glyph => glyphs[self.shape_ind].TextureShadingFlags,
            else => 0,
        };
    }
};

/// A hit the march has checked against the shape itself.
const SurfaceHit = struct {
    Found: bool,
    Object: ObjectData,
    T: f32,
    Normal: Vec3(f32),
    TextureUV: Vec3(f32),

    const none: SurfaceHit = .{
        .Found = false,
        .Object = .{ .shape_type = .None, .shape_ind = 0 },
        .T = 0,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
    };
};

/// Only a plate's front is drawn. Its back or thin sides, or a ray starting inside it, is nothing there.
fn IsFrontHit(hit: HitInfo) bool {
    if (!hit.IsHit() or hit.StartedInside) return false;
    const face = hit.Face orelse return false;
    return face == .PosZ;
}

const MAX_SKIPS: u32 = 4;

/// What one edge's march ignores: the object the edge starts on, and any the march has come within
/// epsilon of and SurfaceAt turned down. A straight ray can't come back round to a flat plate it has
/// passed, so a turned down object stays skipped for the rest of the edge, which also stops the march
/// sitting on it. When it's full the oldest goes, the one furthest behind the ray. Skipping is only to
/// get past things: an object that drops out and gets touched again is just turned down again.
const SkipList = struct {
    mObjects: [MAX_SKIPS]ObjectData,
    mNext: u32,

    fn Init(first: ObjectData) SkipList {
        var list = SkipList{
            .mObjects = @splat(.{ .shape_type = .None, .shape_ind = 0 }),
            .mNext = 1,
        };
        list.mObjects[0] = first;
        return list;
    }

    fn Add(self: *SkipList, object: ObjectData) void {
        self.mObjects[self.mNext] = object;
        self.mNext = (self.mNext + 1) % MAX_SKIPS;
    }

    fn Contains(self: SkipList, shape_type: ShapeType, shape_ind: usize) bool {
        for (self.mObjects) |object| {
            if (object.shape_type == shape_type and object.shape_ind == shape_ind) return true;
        }
        return false;
    }
};

const NodeArr = [MAX_NODES]Node;
const EdgeArr = [MAX_EDGES]Edge;

const MarchData = extern struct {
    min_dist: f32,
    object: ObjectData,
};

pub fn RayMarcher(comptime quads_type: type, comptime glyphs_type: type, comptime surf_shading_type: type, comptime med_shading_type: type, comptime textures_array_type: type) type {
    return extern struct {
        pub const NO_EDGE: u32 = std.math.maxInt(u32);
        const Self = @This();

        mNodes: NodeArr,
        mEdges: EdgeArr,
        mNodeCount: usize,
        mEdgeCount: usize,
        mDefaultColor: Vec4(f32),
        mQuads: quads_type,
        mGlyphs: glyphs_type,
        mQuadsCount: usize,
        mGlyphsCount: usize,
        mSurfShading: surf_shading_type,
        mMedShading: med_shading_type,
        mPerspectiveFar: f32,

        pub fn March(self: *Self, sample_sampler: anytype, textures_array: textures_array_type) void {
            var edge_ind_stack: Stack(usize, MAX_EDGES) = .empty;
            edge_ind_stack.Push(0);

            while (edge_ind_stack.len > 0) {
                const curr_edge_ind = edge_ind_stack.Pop();
                const curr_edge = self.mEdges[curr_edge_ind];
                const from_point = self.mNodes[@intCast(curr_edge.FromNode)].Point;

                const edge_ray = Ray{ .Origin = from_point, .Dir = curr_edge.Direction };
                var skips = SkipList.Init(curr_edge.SkipObject);
                var surface: SurfaceHit = .none;
                var dist_origin: f32 = 0;

                var i: u32 = 0;
                while (i < MAX_STEPS and dist_origin < self.mPerspectiveFar) : (i += 1) {
                    const point = from_point.AddVec(curr_edge.Direction.MulScalar(dist_origin));
                    const march_data = self.NextSurface(point, skips);
                    if (march_data.min_dist > SurfaceEpsilon(dist_origin)) {
                        dist_origin += march_data.min_dist;
                        continue;
                    }

                    //close enough to count, so ask the shape itself where exactly the ray meets it. only
                    //a plate's front is drawn, and a glyph only where the letter covers it: at its back,
                    //its sides or a gap in the letter the ray goes on to whatever is behind
                    surface = self.SurfaceAt(edge_ray, march_data.object, sample_sampler, textures_array);
                    if (surface.Found) break;
                    skips.Add(march_data.object);
                }

                //out of steps or distance, the ray dies
                if (!surface.Found) {
                    self.mEdges[curr_edge_ind].Length = self.mPerspectiveFar;
                    const miss_node_ind = self.GetNodeIndex();
                    self.mNodes[miss_node_ind] = .{
                        .Point = from_point.AddVec(curr_edge.Direction.MulScalar(dist_origin)),
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

                //the exact point on the surface, rather than wherever within epsilon the march stopped
                self.mEdges[curr_edge_ind].Length = surface.T;
                const end_point = from_point.AddVec(curr_edge.Direction.MulScalar(surface.T));
                const shading_handle = self.GetShadingHandle(surface.Object);

                const new_node_ind = self.GetNodeIndex();
                self.mNodes[new_node_ind] = Node{
                    .Point = end_point,
                    .Normal = surface.Normal,
                    .ParentEdge = @intCast(curr_edge_ind),
                    .FirstEdge = NO_EDGE,
                    .MaterialHandle = shading_handle,
                    .AccumColor = self.mDefaultColor,
                    .TextureUV = surface.TextureUV,
                    .ShapeT = surface.Object.shape_type,
                };

                self.mEdges[curr_edge_ind].ToNode = @intCast(new_node_ind);

                //now for checking if we need to spawn more edges based off different material properties of the object
                //in the future can expand this to do reflectivity, lighting, shadows, refraction, whatever else exists idk
                const shading_flags = self.GetShadingFlags(surface.Object);

                //if transparent bit is set, aka it can be some level of transparent and we are not already full of edges.
                //mEdgeCount is the real bound: the stack is popped before each push so it never fills, and
                //each edge adds exactly one node, so this also keeps mNodeCount <= MAX_NODES
                if (shading_flags & SurfShadingData.FLAG_TRANSPARENT != 0 and self.mEdgeCount < MAX_EDGES and !edge_ind_stack.IsFull()) {
                    const new_node = self.mNodes[new_node_ind];
                    const material_handle = new_node.MaterialHandle;
                    const material = self.mSurfShading[material_handle];

                    const texture_color = SampleTexture(new_node.TextureUV, sample_sampler, textures_array);
                    const material_color = Vec4(f32).FromVector(material.Color);
                    const color = material_color.MulVec(texture_color); // tint
                    const alpha = color.w;
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
                            .SkipObject = surface.Object,
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

        fn NextSurface(self: Self, point: Vec3(f32), skips: SkipList) MarchData {
            var data = MarchData{ .min_dist = self.mPerspectiveFar, .object = .{ .shape_type = .None, .shape_ind = 0 } };

            for (0..self.mQuadsCount) |i| {
                if (skips.Contains(.Quad, i)) continue;
                const dist = SDFFunc.sdIMQuad(point, self.mQuads[i]);
                if (dist < data.min_dist) {
                    data.min_dist = dist;
                    data.object.shape_type = .Quad;
                    data.object.shape_ind = @intCast(i);
                }
            }
            for (0..self.mGlyphsCount) |i| {
                if (skips.Contains(.Glyph, i)) continue;
                const dist = SDFFunc.sdIMGlyph(point, self.mGlyphs[i]);
                if (dist < data.min_dist) {
                    data.min_dist = dist;
                    data.object.shape_type = .Glyph;
                    data.object.shape_ind = @intCast(i);
                }
            }
            return data;
        }

        /// Where the ray meets `object`, if it does in a way that's drawn: the front of a plate, and for
        /// a glyph, only where the letter covers it.
        fn SurfaceAt(self: Self, ray: Ray, object: ObjectData, sample_sampler: anytype, textures_array: textures_array_type) SurfaceHit {
            switch (object.shape_type) {
                .Quad => {
                    const quad: QuadData = self.mQuads[object.shape_ind];
                    const hit = SDFFunc.rayIMQuad(ray, quad);
                    if (!IsFrontHit(hit)) return .none;

                    const texture_shading_data = self.mSurfShading[quad.ShadingHandle];
                    return .{
                        .Found = true,
                        .Object = object,
                        .T = hit.T,
                        .Normal = hit.Normal,
                        .TextureUV = SDFFunc.TextureUV(
                            texture_shading_data.Texturehandle,
                            hit.UV,
                            texture_shading_data.TextureWidth,
                            texture_shading_data.TextureHeight,
                        ),
                    };
                },
                .Glyph => {
                    const glyph: GlyphData = self.mGlyphs[object.shape_ind];
                    const hit = SDFFunc.rayIMGlyph(ray, glyph);
                    if (!IsFrontHit(hit)) return .none;

                    //the coverage test needs where in the glyph's box the hit is. the fill texture's UV
                    //is a different thing, a spot in its texture manager slot, and only for color
                    const atlas_shading_data = self.mSurfShading[glyph.AtlasShadingHandle];
                    if (SDFFunc.GetMSD(hit.UV, atlas_shading_data, textures_array, sample_sampler) < 0.5) return .none;

                    const texture_shading_data = self.mSurfShading[atlas_shading_data.SiblingShading];
                    return .{
                        .Found = true,
                        .Object = object,
                        .T = hit.T,
                        .Normal = hit.Normal,
                        .TextureUV = SDFFunc.TextureUV(
                            texture_shading_data.Texturehandle,
                            hit.UV,
                            texture_shading_data.TextureWidth,
                            texture_shading_data.TextureHeight,
                        ),
                    };
                },
                else => return .none,
            }
        }

        fn CalcNodeColor(self: *Self, node_ind: u32, sample_sampler: anytype, textures_array: textures_array_type) void {
            const curr_node = self.mNodes[node_ind];

            const child_accum = if (curr_node.FirstEdge == NO_EDGE) self.mDefaultColor else self.mEdges[@intCast(curr_node.FirstEdge)].AccumColor;

            const material = self.mSurfShading[curr_node.MaterialHandle];
            const texture_color = SampleTexture(curr_node.TextureUV, sample_sampler, textures_array);
            const material_color = Vec4(f32).FromVector(material.Color);
            const color = material_color.MulVec(texture_color); // tint
            const alpha = color.w;

            self.mNodes[node_ind].AccumColor = color.Lerp(child_accum, 1.0 - alpha);
        }

        fn CalcEdgeColor(self: *Self, edge_ind: u32) void {
            const curr_edge = self.mEdges[edge_ind];
            const to_node = self.mNodes[curr_edge.ToNode];
            const from_node = self.mNodes[curr_edge.FromNode];

            const child_accum = to_node.AccumColor;

            const material = self.mMedShading[from_node.MaterialHandle];

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
            if (texture_uv.x < 0 or texture_uv.y < 0 or texture_uv.z < 0) return Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };

            return .FromVector(sample_sampler(textures_array, texture_uv.ToVector(), 0.0));
        }

        fn GetShadingHandle(self: Self, obj_data: ObjectData) u32 {
            return switch (obj_data.shape_type) {
                .Quad => self.mQuads[obj_data.shape_ind].ShadingHandle,
                .Glyph => self.mGlyphs[obj_data.shape_ind].AtlasShadingHandle,
                else => 0,
            };
        }

        fn GetShadingFlags(self: Self, obj_data: ObjectData) u32 {
            return switch (obj_data.shape_type) {
                .Quad => self.mQuads[obj_data.shape_ind].ShadingFlags,
                .Glyph => self.mGlyphs[obj_data.shape_ind].TextureShadingFlags,
                else => 0,
            };
        }
    };
}
