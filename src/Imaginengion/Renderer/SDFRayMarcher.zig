const std = @import("std");
const QuadData = @import("Renderer2D.zig").QuadData;
const GlyphData = @import("Renderer2D.zig").GlyphData;
const ShadingData = @import("Renderer.zig").ShadingData;

const MathTypes = @import("../Math/MathTypes.zig");
const Ray = MathTypes.Ray;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const SDFFunctions = @import("../Math/SDFFunctions.zig");
const IMQuad = SDFFunctions.IMQuad;
const IMGlyph = SDFFunctions.IMGlyph;

const THICKNESS_2D = SDFFunctions.THICKNESS_2D;

const Stack = @import("../Core/Stack.zig").Stack;

const MAX_STEPS: u32 = 9999;
const SURF_DIST: f32 = 0.00099;
pub const MAX_NODES: u32 = 8;
pub const MAX_EDGES: u32 = 8;
pub const DEFAULT_COLOR = Vec4(f32){ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1.0 };

//NOTE: This is a medium which we travel through
//contains details related to the medium
pub const Node = struct {
    ParentEdge: i32, //if ParentEdge == -1 -> root parent
    MaterialHandle: u32,
    FirstEdge: i32, //if FirstEdge == -1 -> leaf
    AccumColor: Vec4(f32),

    pub fn CalcColor(self: *Node, materials: anytype, edges: *EdgeArr) void {
        const child_accum = if (self.FirstEdge == -1) DEFAULT_COLOR else edges[@intCast(self.FirstEdge)].AccumColor;

        const material: ShadingData = materials[self.MaterialHandle];
        const color = Vec4(f32).FromVector(material.Color);
        const alpha = color.w;

        self.AccumColor = color.Lerp(child_accum, 1.0 - alpha);
    }
};

//NOTE: This is the ray we travel according to the ray
//stores information for ray
pub const Edge = struct {
    Ray: Ray(f32),
    Length: f32,
    FromNode: i32,
    ToNode: i32, //if ToNode == -1 -> miss
    SiblingEdge: i32, //used if a node has multiple rays (multiple edges)
    Normal: Vec3(f32),
    AccumColor: Vec4(f32),
    MaterialHandle: u32,

    pub fn CalcColor(self: *Edge, materials: anytype, nodes: *NodeArr) void {
        const child_accum = if (self.ToNode == -1) DEFAULT_COLOR else nodes[@intCast(self.ToNode)].AccumColor;

        const material: ShadingData = materials[self.MaterialHandle];

        // Beer-Lambert for absorbtion
        const rgb = Vec3(f32).FromVector(-material.Absorption).MulScalar(self.Length).Exp().MulVec(Vec3(f32){ .x = child_accum.x, .y = child_accum.y, .z = child_accum.z });

        self.AccumColor = .{ .x = rgb.x, .y = rgb.y, .z = rgb.z, .w = child_accum.w };
    }
};

const ShapeType = enum(u32) {
    None = 0,
    Quad,
    Glyph,
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
            .Glyph => glyphs[self.shape_ind].TextureShadingHandle,
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

const NodeArr = [MAX_NODES]Node;
const EdgeArr = [MAX_EDGES]Edge;

const MarchData = extern struct {
    min_dist: f32,
    object: ObjectData,
};

pub fn RayMarcher(ssbo_type: type) type {
    return struct {
        const Self = @This();

        mNodes: NodeArr,
        mEdges: EdgeArr,
        mNodeCount: usize,
        mEdgeCount: usize,
        mShadingSSBO: ssbo_type,

        pub fn March(self: *Self, quads: anytype, glyphs: anytype, quad_count: usize, glyph_count: usize, perspective_far: f32) void {
            var edge_ind_stack: Stack(usize, MAX_EDGES) = undefined;
            edge_ind_stack.push(0);

            while (edge_ind_stack.len > 0) {
                const curr_edge_ind = edge_ind_stack.pop();
                const curr_edge = self.mEdges[curr_edge_ind];

                var i: u32 = 0;
                var march_data: MarchData = .{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
                var dist_origin: f32 = 0;

                while (i < MAX_STEPS and dist_origin < perspective_far and march_data.min_dist > SURF_DIST) : (i += 1) {
                    march_data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
                    const point = curr_edge.Ray.Origin.AddVec(curr_edge.Ray.Direction.MulScalar(dist_origin));
                    march_data = NextSurface(point, quads, glyphs, quad_count, glyph_count);
                    dist_origin += march_data.min_dist;
                }
                //once we are herer we either a) hit max steps, b) hit our max distance, c) hit a surface

                //case a and b - ray dies for whatever reason
                if (i >= MAX_STEPS or dist_origin >= perspective_far) {
                    self.mEdges[curr_edge_ind].ToNode = -1;
                    self.mEdges[curr_edge_ind].Length = dist_origin;
                    continue;
                }

                //case c
                const hit_point = curr_edge.Ray.Origin.AddVec(curr_edge.Ray.Direction.MulScalar(dist_origin));
                const hit_normal = CalcNormal(hit_point, quads, glyphs, quad_count, glyph_count);

                // fill in current edge
                self.mEdges[curr_edge_ind].Length = dist_origin;
                self.mEdges[curr_edge_ind].Normal = hit_normal;

                const shading_handle = march_data.object.GetShadingHandle(quads, glyphs);

                const new_node_ind = self.GetNodeIndex();
                self.mNodes[new_node_ind] = Node{
                    .ParentEdge = @intCast(curr_edge_ind),
                    .MaterialHandle = shading_handle,
                    .FirstEdge = -1,
                    .AccumColor = DEFAULT_COLOR,
                };

                self.mEdges[curr_edge_ind].ToNode = @intCast(new_node_ind);

                const shading_flags = march_data.object.GetShadingFlags(quads, glyphs);

                //in the future can expand this to do translucency, reflectivity, lighting, shadows, refraction, whatever else exists idk
                //for now if the object is translucent make a ray that goes straight through
                if (shading_flags & ShadingData.SHADING_FLAG_TRANSPARENT != 0) { //if transparent bit is set, aka it is transparent
                    const new_edge_ind = self.GetEdgeIndex();

                    const nudged_origin = if (march_data.object.Is2D()) hit_point.AddVec(curr_edge.Ray.Direction.MulScalar(SURF_DIST)).AddScalar(THICKNESS_2D) else hit_point.AddVec(curr_edge.Ray.Direction.MulScalar(SURF_DIST));

                    self.mEdges[new_edge_ind] = Edge{
                        .Ray = Ray(f32){
                            .Origin = nudged_origin,
                            .Direction = curr_edge.Ray.Direction, // same dir, straight through
                        },
                        .Length = -1.0,
                        .Normal = .{ .x = 0, .y = 0, .z = 0 },
                        .FromNode = @intCast(new_node_ind),
                        .ToNode = -1,
                        .SiblingEdge = -1,
                        .AccumColor = Vec4(f32){ .x = 0, .y = 0, .z = 0, .w = 0 },
                    };

                    self.mNodes[new_node_ind].FirstEdge = @intCast(new_edge_ind);
                    edge_ind_stack.push(new_edge_ind);
                }
            }
        }

        pub fn GenerateColor(self: *Self, materials: anytype) Vec4(f32).VectorT {
            var i: usize = self.mNodeCount;
            while (i > 0) {
                i -= 1;
                const node = &self.mNodes[i];

                var ei: i32 = node.FirstEdge;
                while (ei != -1) {
                    const edge = &self.mEdges[@intCast(ei)];
                    edge.CalcColor(materials, &self.mNodes);
                    ei = edge.SiblingEdge;
                }

                node.CalcColor(materials, &self.mEdges);
            }

            return self.mNodes[0].AccumColor.ToVector();
        }

        fn GetNodeIndex(self: *Self) usize {
            defer self.mNodeCount += 1;
            return self.mNodeCount;
        }

        fn GetEdgeIndex(self: *Self) usize {
            defer self.mEdgeCount += 1;
            return self.mEdgeCount;
        }

        fn NextSurface(point: Vec3(f32), quads: anytype, glyphs: anytype, quad_count: usize, glyph_count: usize) MarchData {
            var data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };

            var i: u32 = 0;
            while (i < quad_count) : (i += 1) {
                const dist = IMQuad(point, quads[i]);
                if (dist < data.min_dist) {
                    data.min_dist = dist;
                    data.object.shape_type = .Quad;
                    data.object.shape_ind = @intCast(i);
                }
            }
            i = 0;
            while (i < glyph_count) : (i += 1) {
                const dist = IMGlyph(point, glyphs[i]);
                if (dist < data.min_dist) {
                    data.min_dist = dist;
                    data.object.shape_type = .Glyph;
                    data.object.shape_ind = @intCast(i);
                }
            }
            return data;
        }

        fn CalcNormal(point: Vec3(f32), quads: anytype, glyphs: anytype, quad_count: usize, glyph_count: usize) Vec3(f32) {
            const e: f32 = 0.001;

            const x = Vec3(f32){ .x = e, .y = 0, .z = 0 };
            const neg_x = Vec3(f32){ .x = -e, .y = 0, .z = 0 };
            const y = Vec3(f32){ .x = 0, .y = e, .z = 0 };
            const neg_y = Vec3(f32){ .x = 0, .y = -e, .z = 0 };
            const z = Vec3(f32){ .x = 0, .y = 0, .z = e };
            const neg_z = Vec3(f32){ .x = 0, .y = 0, .z = -e };

            const next_surf_x = NextSurface(point.AddVec(x), quads, glyphs, quad_count, glyph_count);
            const next_surf_neg_x = NextSurface(point.AddVec(neg_x), quads, glyphs, quad_count, glyph_count);
            const next_surf_y = NextSurface(point.AddVec(y), quads, glyphs, quad_count, glyph_count);
            const next_surf_neg_y = NextSurface(point.AddVec(neg_y), quads, glyphs, quad_count, glyph_count);
            const next_surf_z = NextSurface(point.AddVec(z), quads, glyphs, quad_count, glyph_count);
            const next_surf_neg_z = NextSurface(point.AddVec(neg_z), quads, glyphs, quad_count, glyph_count);

            const dx = next_surf_x.min_dist - next_surf_neg_x.min_dist;
            const dy = next_surf_y.min_dist - next_surf_neg_y.min_dist;
            const dz = next_surf_z.min_dist - next_surf_neg_z.min_dist;

            const vec = Vec3(f32){ .x = dx, .y = dy, .z = dz };

            return vec.Dir();
        }
    };
}
