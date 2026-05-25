const std = @import("std");
const QuadData = @import("Renderer2D.zig").QuadData;
const GlyphData = @import("Renderer2D.zig").GlyphData;

const MathTypes = @import("../Math/MathTypes.zig");
const Ray = MathTypes.Ray;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const SDFFunctions = @import("../Math/SDFFunctions.zig");
const IMQuad = SDFFunctions.IMQuad;
const ImGlyph = SDFFunctions.IMGlyph;

const THICKNESS_2D = SDFFunctions.THICKNESS_2D;

const Stack = @import("../Core/Stack.zig").Stack;

const RayMarcher = @This();

const MAX_STEPS: u32 = 9999;
const SURF_DIST: f32 = 0.00099;
const MAX_NODES: u32 = 8;
const MAX_EDGES: u32 = 8;

//NOTE: This is a medium which we travel through
//contains details related to the medium
const Node = struct {
    ParentEdge: i32, //if ParentEdge == -1 -> root parent
    SurfaceColor: Vec4(f32),
    Is2D: bool,
    FirstEdge: i32, //if FirstEdge == -1 -> leaf
};

//NOTE: This is the ray we travel according to the ray
//stores information for ray
const Edge = struct {
    Ray: Ray(f32),
    Length: f32, //if Length == -1 -> miss
    FromNode: i32,
    ToNode: i32, //if ToNode == -1 -> miss
    SiblingEdge: i32, //used if a node has multiple rays (multiple edges)
    Normal: Vec3(f32),
    AccumColor: Vec4(f32),
};

const ShapeType = enum(u32) {
    None = 0,
    Quad,
    Glyph,
};

const ObjectData = extern struct {
    shape_type: ShapeType,
    shape_ind: u32,

    pub fn Equals(self: ObjectData, other: ObjectData) bool {
        if (self.shape_type == other.shape_type and self.shape_ind == other.shape_ind) return true else false;
    }
    pub fn Is2D(self: ObjectData) bool {
        if (self.shape_type == ShapeType.Quad or self.shape_type == ShapeType.Glyph) return true;
        return false;
    }
};

const MarchData = extern struct {
    min_dist: f32,
    object: ObjectData,
};

mNodes: [MAX_NODES]Node = undefined,
mEdges: [MAX_EDGES]Edge = undefined,
mNodeCount: u32 = 0,
mEdgeCount: u32 = 0,
mQuads: []QuadData,
mGlyphs: []GlyphData,
mPerspectiveFar: f32,

pub fn March(self: *RayMarcher) void {
    var edge_ind_stack: Stack(i32, MAX_EDGES) = undefined;
    edge_ind_stack.push(0);

    while (edge_ind_stack.len > 0) {
        const curr_edge_ind = edge_ind_stack.pop();
        const curr_edge = self.mEdges[curr_edge_ind];

        var i: u32 = 0;
        var march_data: MarchData = .{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
        var dist_origin: f32 = 0;

        while (i < MAX_STEPS and dist_origin < self.mPerspectiveFar and march_data.min_dist > SURF_DIST) : (i += 1) {
            march_data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };
            const point = curr_edge.Ray.Origin.AddVec(curr_edge.Ray.Direction.MulScalar(dist_origin));
            march_data = self.NextSurface(point);
            dist_origin += march_data.min_dist;
        }
        //once we are herer we either a) hit max steps, b) hit our max distance, c) hit a surface

        //case a and b - ray dies for whatever reason
        if (i >= MAX_STEPS or dist_origin >= self.mPerspectiveFar) {
            self.mEdges[curr_edge_ind].ToNode = -1;
            self.mEdges[curr_edge_ind].Length = dist_origin;
            continue;
        }

        //case c
        const hit_point = curr_edge.Ray.Origin.AddVec(curr_edge.Ray.Direction.MulScalar(dist_origin));
        const hit_normal = self.CalcNormal(hit_point);

        // fill in current edge
        self.mEdges[curr_edge_ind].Length = dist_origin;
        self.mEdges[curr_edge_ind].Normal = hit_normal;

        const surface_color = self.GetSurfaceColor(march_data.object);

        const new_node_ind = self.GetNodeIndex();
        self.mNodes[new_node_ind] = Node{
            .ParentEdge = curr_edge_ind,
            .SurfaceColor = surface_color,
            .Is2D = march_data.object.Is2D(),
            .FirstEdge = -1,
        };

        self.mEdges[curr_edge_ind].ToNode = new_node_ind;

        //in the future can expand this to do translucency, reflectivity, lighting, shadows, refraction, whatever else exists idk
        //for now if the object is translucent make a ray that goes straight through
        if (surface_color.w < 1.0) {
            const new_edge_ind = self.GetEdgeIndex();

            const nudged_origin = if (march_data.object.Is2D()) hit_point.AddVec(curr_edge.Ray.Direction.MulScalar(SURF_DIST)).AddScalar(THICKNESS_2D) else hit_point.AddVec(curr_edge.Ray.Direction.MulScalar(SURF_DIST));

            self.mEdges[new_edge_ind] = Edge{
                .Ray = Ray(f32){
                    .Origin = nudged_origin,
                    .Direction = curr_edge.Ray.Direction, // same dir, straight through
                },
                .Length = -1.0,
                .Normal = .{ 0, 0, 0 },
                .FromNode = new_node_ind,
                .ToNode = -1,
                .SiblingEdge = -1,
            };

            self.mNodes[new_node_ind].FirstEdge = new_edge_ind;
            edge_ind_stack.push(new_edge_ind);
        }
    }
}

pub fn GenerateColor(self: RayMarcher) Vec4(f32).VectorT {
    const default_color = Vec4(f32){ 0.3, 0.3, 0.3, 1.0 };

    var i: i32 = self.mEdgeCount - 1;
    while (i >= 0) : (i -= 1) {
        const edge = self.mEdges[i];

        if (edge.ToNode == -1) continue;

        const node = self.mNodes[edge.ToNode];

        const child_color = if (node.FirstEdge == -1) default_color else self.mEdges[node.FirstEdge].AccumColor;

        const alpha = node.SurfaceColor.w;
        self.mEdges[i].AccumColor = node.SurfaceColor.Lerp(child_color, 1.0 - alpha);
    }
    return if (self.mEdgeCount > 0) self.mEdges[0].AccumColor else default_color;
}

pub fn GetNodeIndex(self: RayMarcher) u32 {
    defer self.mNodeCount += 1;
    return self.mNodeCount;
}

pub fn GetEdgeIndex(self: RayMarcher) Edge {
    defer self.mEdgeCount += 1;
    return self.mEdgeCount;
}

fn GetSurfaceColor(self: RayMarcher, obj: ObjectData) Vec4(f32) {
    switch (obj.shape_type) {
        .Quad => return Vec4(f32).FromVector(self.mQuads[obj.shape_ind].Color),
        .Glyph => return Vec4(f32).FromVector(self.mGlyphs[obj.shape_ind].Color),
        else => return Vec4(f32){ 0.3, 0.3, 0.3, 1.0 },
    }
}

fn NextSurface(self: RayMarcher, point: Vec3(f32)) MarchData {
    var data = MarchData{ .min_dist = std.math.floatMax(f32), .object = .{ .shape_type = .None, .shape_ind = 0 } };

    for (self.mQuads, 0..) |quad, i| {
        if (self.mExclusions.contains(.{ .shape_type = .Quad, .shape_ind = i })) continue;
        const dist = IMQuad(point, quad.Position, quad.Rotation, quad.Scale);
        if (dist < data.min_dist) {
            data.min_dist = dist;
            data.object.shape_type = .Quad;
            data.object.shape_ind = @intCast(i);
        }
    }
    for (self.mGlyphs, 0..) |glyph, i| {
        if (self.mExclusions.contains(.{ .shape_type = .Glyph, .shape_ind = i })) continue;
        const dist = ImGlyph(point, glyph);
        if (dist < data.min_dist) {
            data.min_dist = dist;
            data.object.shape_type = .Glyph;
            data.object.shape_ind = @intCast(i);
        }
    }
    return data;
}

fn CalcNormal(self: *RayMarcher, point: Vec3(f32)) Vec3(f32) {
    const e: f32 = 0.001;

    const dx = self.NextSurface(point.AddVec(.{ .x = e, .y = 0, .z = 0 })).min_dist - self.NextSurface(point.AddVec(.{ .x = -e, .y = 0, .z = 0 })).min_dist;
    const dy = self.NextSurface(point.AddVec(.{ .x = 0, .y = e, .z = 0 })).min_dist - self.NextSurface(point.AddVec(.{ .x = 0, .y = -e, .z = 0 })).min_dist;
    const dz = self.NextSurface(point.AddVec(.{ .x = 0, .y = 0, .z = e })).min_dist - self.NextSurface(point.AddVec(.{ .x = 0, .y = 0, .z = -e })).min_dist;
    const vec = Vec3(f32){ .x = dx, .y = dy, .z = dz };
    return vec.Dir();
}
