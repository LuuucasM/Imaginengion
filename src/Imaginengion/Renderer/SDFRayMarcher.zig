const std = @import("std");
const QuadData = @import("Renderer2D.zig").QuadData;
const GlyphData = @import("Renderer2D.zig").GlyphData;
const ShadingData = @import("Renderer.zig").ShadingData;

const MathTypes = @import("../Math/MathTypes.zig");
const Ray = MathTypes.Ray;
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const SDFFunc = @import("../Math/SDFFunctions.zig");

const ShapeType = @import("Renderer.zig").ShapeType;

const THICKNESS_2D = SDFFunc.THICKNESS_2D;

const Stack = @import("../Core/Stack.zig").Stack;

const SampleSampler = @import("../EngineAssets/shaders/SDFFragShaderBase.zig").SampleSampler;

const MAX_STEPS: u32 = 9999;
const SURF_DIST: f32 = 0.00099;
pub const MAX_NODES: u32 = 9;
pub const MAX_EDGES: u32 = 8;
pub const DEFAULT_COLOR = Vec4(f32){ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1.0 };
pub const NO_EDGE: u32 = std.math.maxInt(u32);

//NOTE: This represents a surface that we hit
pub const Node = struct {
    Point: Vec3(f32),
    Normal: Vec3(f32),
    ParentEdge: u32,
    FirstEdge: u32,
    MaterialHandle: u32,
    AccumColor: Vec4(f32),
    TextureUV: Vec3(f32),
    ShapeT: ShapeType,
};

//NOTE: This represents travelling through volume
pub const Edge = struct {
    Direction: Vec3(f32),
    Length: f32,
    FromNode: u32,
    ToNode: u32,
    SiblingEdge: u32,
    AccumColor: Vec4(f32),
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

const NodeArr = [MAX_NODES]Node;
const EdgeArr = [MAX_EDGES]Edge;

const MarchData = extern struct {
    min_dist: f32,
    object: ObjectData,
};

const Self = @This();

mNodes: NodeArr,
mEdges: EdgeArr,
mNodeCount: usize,
mEdgeCount: usize,

pub fn March(self: *Self, quads: anytype, glyphs: anytype, perspective_far: f32) void {
    var edge_ind_stack: Stack(usize, MAX_EDGES) = undefined;
    edge_ind_stack.Push(0);

    while (edge_ind_stack.len > 0) {
        const curr_edge_ind = edge_ind_stack.Pop();
        const curr_edge = self.mEdges[curr_edge_ind];
        const from_point = self.mNodes[@intCast(curr_edge.FromNode)].Point;

        var i: u32 = 0;
        var march_data: MarchData = .{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
        var dist_origin: f32 = 0;

        while (i < MAX_STEPS and dist_origin < perspective_far and march_data.min_dist > SURF_DIST) : (i += 1) {
            march_data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
            const point = from_point.AddVec(curr_edge.Direction.MulScalar(dist_origin));
            march_data = NextSurface(point, quads, glyphs);
            dist_origin += march_data.min_dist;
        }
        //once we are herer we either a) hit max steps, b) hit our max distance, c) hit a surface

        self.mEdges[curr_edge_ind].Length = dist_origin;
        const end_point = from_point.AddVec(curr_edge.Direction.MulScalar(dist_origin));

        //case a and b - ray dies
        if (i >= MAX_STEPS or dist_origin >= perspective_far) {
            const miss_node_ind = self.GetNodeIndex();
            self.mNodes[miss_node_ind] = .{
                .Point = end_point,
                .Normal = .{ .x = 0, .y = 0, .z = 0 },
                .ParentEdge = @intCast(curr_edge_ind),
                .FirstEdge = NO_EDGE,
                .MaterialHandle = 0,
                .AccumColor = DEFAULT_COLOR,
                .TextureUV = .{ .x = 0, .y = 0 },
                .ShapeT = .None,
            };
            self.mEdges[curr_edge_ind].ToNode = @intCast(miss_node_ind);
            continue;
        }

        //calculate the normal
        const hit_normal = CalcNormal(end_point, quads, glyphs);

        const shading_handle = march_data.object.GetShadingHandle(quads, glyphs);

        //calculate UV if there is one
        const texture_uv = switch (march_data.object.shape_type) {
            .Quad => blk: {
                //calculate the UV based off the texture_handle
                const quad: QuadData = quads[march_data.object.shape_ind];
                break :blk SDFFunc.uvIMQuad(end_point, quad);
            },
            .Glyph => blk: {
                //TODO: i need to first get the uv for the atlas and then test the MSD
                //if the msd > 0.5 then we need to get the
                const glyph: GlyphData = glyphs[march_data.object.shape_ind];
                break :blk SDFFunc.uvIMGlyph(end_point, glyph);
            },
            else => Vec2(f32){ .x = -1, .y = -1 },
        };

        const new_node_ind = self.GetNodeIndex();
        self.mNodes[new_node_ind] = Node{
            .Point = end_point,
            .Normal = hit_normal,
            .ParentEdge = @intCast(curr_edge_ind),
            .FirstEdge = NO_EDGE,
            .MaterialHandle = shading_handle,
            .AccumColor = DEFAULT_COLOR,
            .TextureUV = texture_uv,
            .ShapeT = march_data.object.shape_type,
        };

        self.mEdges[curr_edge_ind].ToNode = @intCast(new_node_ind);

        //now for checking if we need to spawn more edges based off different material properties of the object
        //in the future can expand this to do reflectivity, lighting, shadows, refraction, whatever else exists idk
        const shading_flags = march_data.object.GetShadingFlags(quads, glyphs);

        if (shading_flags & ShadingData.SHADING_FLAG_TRANSPARENT != 0 and !edge_ind_stack.IsFull()) { //if transparent bit is set, aka it can be some level of transparent
            //TODO: first sample the texture to get the color and the material color and check to see if
            //its actually transparent
            //if its actually transparent then yes make a new edge and put it onto the stack
            //if its actually opaque then skip adding a new edge
            const new_edge_ind = self.GetEdgeIndex();

            self.mEdges[new_edge_ind] = Edge{
                .Direction = curr_edge.Direction,
                .Length = 0,
                .FromNode = @intCast(new_node_ind),
                .ToNode = 0,
                .SiblingEdge = NO_EDGE,
                .AccumColor = DEFAULT_COLOR,
            };

            self.mNodes[new_node_ind].FirstEdge = @intCast(new_edge_ind);
            edge_ind_stack.Push(new_edge_ind);
        }
    }
}

pub fn GenerateColor(self: *Self, materials: anytype, textures_array: anytype) Vec4(f32).VectorT {
    var i: usize = self.mNodeCount;
    while (i > 0) {
        i -= 1;
        const node = self.mNodes[i];

        var ei: u32 = node.FirstEdge;
        while (ei != NO_EDGE) {
            self.CalcEdgeColor(materials, ei);
            ei = self.mEdges[@intCast(ei)].SiblingEdge;
        }
        self.CalcNodeColor(materials, i, textures_array);
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

fn NextSurface(point: Vec3(f32), quads: anytype, glyphs: anytype) MarchData {
    var data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };

    for (quads, 0..) |quad, i| {
        const dist = SDFFunc.sdIMQuad(point, quad);
        if (dist < data.min_dist) {
            data.min_dist = dist;
            data.object.shape_type = .Quad;
            data.object.shape_ind = @intCast(i);
        }
    }
    for (glyphs, 0..) |glyph, i| {
        const dist = SDFFunc.sdIMGlyph(point, glyph);
        if (dist < data.min_dist) {
            data.min_dist = dist;
            data.object.shape_type = .Glyph;
            data.object.shape_ind = @intCast(i);
        }
    }
    return data;
}

fn CalcNormal(point: Vec3(f32), quads: anytype, glyphs: anytype) Vec3(f32) {
    const e: f32 = 0.001;

    const x = Vec3(f32){ .x = e, .y = 0, .z = 0 };
    const neg_x = Vec3(f32){ .x = -e, .y = 0, .z = 0 };
    const y = Vec3(f32){ .x = 0, .y = e, .z = 0 };
    const neg_y = Vec3(f32){ .x = 0, .y = -e, .z = 0 };
    const z = Vec3(f32){ .x = 0, .y = 0, .z = e };
    const neg_z = Vec3(f32){ .x = 0, .y = 0, .z = -e };

    const next_surf_x = NextSurface(point.AddVec(x), quads, glyphs);
    const next_surf_neg_x = NextSurface(point.AddVec(neg_x), quads, glyphs);
    const next_surf_y = NextSurface(point.AddVec(y), quads, glyphs);
    const next_surf_neg_y = NextSurface(point.AddVec(neg_y), quads, glyphs);
    const next_surf_z = NextSurface(point.AddVec(z), quads, glyphs);
    const next_surf_neg_z = NextSurface(point.AddVec(neg_z), quads, glyphs);

    const dx = next_surf_x.min_dist - next_surf_neg_x.min_dist;
    const dy = next_surf_y.min_dist - next_surf_neg_y.min_dist;
    const dz = next_surf_z.min_dist - next_surf_neg_z.min_dist;

    const vec = Vec3(f32){ .x = dx, .y = dy, .z = dz };

    return vec.Dir();
}

fn CalcNodeColor(self: *Self, materials: anytype, node_ind: u32) void {
    const curr_node = self.mNodes[node_ind];

    const child_accum = if (curr_node.FirstEdge == NO_EDGE) DEFAULT_COLOR else self.mEdges[@intCast(curr_node.FirstEdge)].AccumColor;

    const material: ShadingData = materials[curr_node.MaterialHandle];
    switch (curr_node.ShapeT) {
        .Quad => {
            const texture_color = SampleTexture(curr_node.TextureUV);
            const material_color = Vec4(f32).FromVector(material.Color);
            const color = material_color.Mul(texture_color); // tint
            const alpha = color.w;
            self.mNodes[node_ind].AccumColor = color.Lerp(child_accum, 1.0 - alpha);
        },
        .Glyph => {
            const color = Vec4(f32).FromVector(material.Color);
            const alpha = color.w;
            self.mNodes[node_ind].AccumColor = color.Lerp(child_accum, 1.0 - alpha);
        },
        else => self.mNodes[node_ind].AccumColor = child_accum,
    }
}

fn CalcEdgeColor(self: *Self, materials: anytype, edge_ind: u32) void {
    const curr_edge = self.mEdges[edge_ind];
    const to_node = self.mNodes[curr_edge.ToNode];
    const from_node = self.mNodes[curr_edge.FromNode];

    const child_accum = to_node.AccumColor;

    const material: ShadingData = materials[from_node.MaterialHandle];

    // Beer-Lambert for absorbtion  over edge length
    const rgb = Vec3(f32).FromVector(-material.Absorption).MulScalar(curr_edge.Length).Exp().MulVec(Vec3(f32){ .x = child_accum.x, .y = child_accum.y, .z = child_accum.z });

    self.mEdges[edge_ind].AccumColor = .{ .x = rgb.x, .y = rgb.y, .z = rgb.z, .w = child_accum.w };
}

fn SampleTexture(texture_uv: Vec3(f32)) Vec4(f32) {
    if (texture_uv.x < 0 or texture_uv.y < 0 or texture_uv.z < 0) return Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };

    return SampleSampler(.{ .descriptor = .{ .set = 2, .binding = 0 } }, texture_uv);
}
