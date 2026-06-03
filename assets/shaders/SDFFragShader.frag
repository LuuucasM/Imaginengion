#version 460

// ─── Constants ───────────────────────────────────────────────────────────────
const uint  MAX_STEPS   = 9999;
const float SURF_DIST   = 0.00099;
const uint  MAX_NODES   = 8;
const uint  MAX_EDGES   = 8;
const float THICKNESS_2D = 0.001;
const float FLOAT_MAX   = 3.402823466e+38;

const uint SHAPE_NONE  = 0;
const uint SHAPE_QUAD  = 1;
const uint SHAPE_GLYPH = 2;

// ─── Output ──────────────────────────────────────────────────────────────────
layout(location = 0) out vec4 oFragColor;

// ─── UBO ─────────────────────────────────────────────────────────────────────
layout(set = 3, binding = 0) uniform CameraUBOBlock {
    vec3  mPosition;
    float mPerspectiveFar;
    vec4  mRotation;
    vec2  mRayScale;
    vec2  mRayOffset;
    uint  mQuadsCount;
    uint  mGlyphsCount;
} CameraUBO;

// ─── SSBOs ───────────────────────────────────────────────────────────────────
struct QuadData {
    vec3  Position;
    float _pad0;
    vec4  Rotation;
    vec3  Scale;
    float _pad1;
    float TilingFactor;
    uint  TextureHandle;
    uint  _pad2_0;
    uint  _pad2_1;
    vec4  Color;
    vec2  TextureUV0;
    vec2  TextureUV1;
};

layout(set = 2, binding = 1) readonly buffer QuadsSSBOBlock {
    QuadData data[];
} QuadsSSBO;

struct GlyphData {
    vec3  Position;
    float Scale;
    vec4  Rotation;
    float TilingFactor;
    uint  _pad0_0;
    uint  _pad0_1;
    uint  _pad0_2;
    vec4  Color;
    vec2  TextureUV0;
    vec2  TextureUV1;
    vec2  AtlasUV0;
    vec2  AtlasUV1;
    vec2  PlaneMin;
    vec2  PlaneMax;
    uint  AtlasHandle;
    uint  TextureHandle;
    uint  _pad1_0;
    uint  _pad1_1;
};

layout(set = 2, binding = 2) readonly buffer GlyphsSSBOBlock {
    GlyphData data[];
} GlyphsSSBO;

// ─── Math helpers ─────────────────────────────────────────────────────────────
vec3 quatRotate(vec4 q, vec3 v) {
    vec3 qv = q.yzw;   // x,y,z components
    float qw = q.x;    // w component
    return v + 2.0 * cross(qv, cross(qv, v) + qw * v);
}

vec3 invQuatRotate(vec4 q, vec3 v) {
    return quatRotate(vec4(q.x, -q.yzw), v);
}

// ─── SDF functions ───────────────────────────────────────────────────────────
float sdBox(vec3 point, vec3 half_extents) {
    vec3 q = abs(point) - half_extents;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdGlyph(vec3 point, GlyphData data) {
    float left   = data.PlaneMin.x;
    float top    = data.PlaneMin.y;
    float right  = data.PlaneMax.x;
    float bottom = data.PlaneMax.y;

    vec2 plane_size   = vec2((right - left)  * data.Scale,
                             (top   - bottom) * data.Scale);
    vec2 plane_center = vec2((left + right)  * 0.5 * data.Scale,
                             (top  + bottom)  * 0.5 * data.Scale);

    vec3 p2 = vec3(point.x - plane_center.x,
                   point.y - plane_center.y,
                   point.z);

    return sdBox(p2, vec3(plane_size.x * 0.5, plane_size.y * 0.5, THICKNESS_2D));
}

float IMQuad(vec3 point, vec3 translation, vec4 rotation, vec3 scale) {
    return sdBox(
        invQuatRotate(rotation, point - translation),
        vec3(scale.x * 0.5, scale.y * 0.5, THICKNESS_2D)
    );
}

float IMGlyph(vec3 point, GlyphData data) {
    return sdGlyph(
        invQuatRotate(data.Rotation, point - data.Position),
        data
    );
}

// ─── RayMarcher types ────────────────────────────────────────────────────────
struct ObjectData {
    uint shape_type;
    uint shape_ind;
};

struct MarchData {
    float      min_dist;
    ObjectData object;
};

struct Ray {
    vec3 Origin;
    vec3 Direction;
};

struct Node {
    int  ParentEdge;
    vec4 SurfaceColor;
    bool Is2D;
    int  FirstEdge;
};

struct Edge {
    Ray  ray;
    float Length;
    int  FromNode;
    int  ToNode;
    int  SiblingEdge;
    vec3 Normal;
    vec4 AccumColor;
};

// ─── RayMarcher state ────────────────────────────────────────────────────────
Node mNodes[MAX_NODES];
Edge mEdges[MAX_EDGES];
uint mNodeCount;
uint mEdgeCount;
ObjectData mCurrObject;

// ─── RayMarcher functions ────────────────────────────────────────────────────
bool objectIs2D(ObjectData obj) {
    return obj.shape_type == SHAPE_QUAD || obj.shape_type == SHAPE_GLYPH;
}

MarchData NextSurface(vec3 point) {
    MarchData data;
    data.min_dist         = FLOAT_MAX;
    data.object.shape_type = SHAPE_NONE;
    data.object.shape_ind  = 0;

    for (uint i = 0; i < CameraUBO.mQuadsCount; i++) {
        float dist = IMQuad(point,
                            QuadsSSBO.data[i].Position,
                            QuadsSSBO.data[i].Rotation,
                            QuadsSSBO.data[i].Scale);
        if (dist < data.min_dist) {
            data.min_dist          = dist;
            data.object.shape_type = SHAPE_QUAD;
            data.object.shape_ind  = i;
            if (dist < 0.0) {
                return dist;
            }
        }

    }

    for (uint i = 0; i < CameraUBO.mGlyphsCount; i++) {
        float dist = IMGlyph(point, GlyphsSSBO.data[i]);
        if (dist < data.min_dist) {
            data.min_dist          = dist;
            data.object.shape_type = SHAPE_GLYPH;
            data.object.shape_ind  = i;
            if (dist < 0.0) {
                return dist;
            }
        }

    }

    return data;
}

vec3 CalcNormal(vec3 point) {
    const float e = 0.001;
    float dx = NextSurface(point + vec3( e, 0, 0)).min_dist
             - NextSurface(point + vec3(-e, 0, 0)).min_dist;
    float dy = NextSurface(point + vec3(0,  e, 0)).min_dist
             - NextSurface(point + vec3(0, -e, 0)).min_dist;
    float dz = NextSurface(point + vec3(0, 0,  e)).min_dist
             - NextSurface(point + vec3(0, 0, -e)).min_dist;
    return normalize(vec3(dx, dy, dz));
}

vec4 GetSurfaceColor(ObjectData obj) {
    if (obj.shape_type == SHAPE_QUAD)  return QuadsSSBO.data[obj.shape_ind].Color;
    if (obj.shape_type == SHAPE_GLYPH) return GlyphsSSBO.data[obj.shape_ind].Color;
    return vec4(0.3, 0.3, 0.3, 1.0);
}

uint GetNodeIndex() {
    uint idx = mNodeCount;
    mNodeCount++;
    return idx;
}

uint GetEdgeIndex() {
    uint idx = mEdgeCount;
    mEdgeCount++;
    return idx;
}

void March() {
    int  edge_stack[MAX_EDGES];
    uint stack_len = 0;
    edge_stack[stack_len++] = 0;

    while (stack_len > 0) {
        int  curr_edge_ind = edge_stack[--stack_len];
        Edge curr_edge     = mEdges[curr_edge_ind];

        MarchData march_data;
        march_data.min_dist          = FLOAT_MAX;
        march_data.object.shape_type = SHAPE_NONE;
        march_data.object.shape_ind  = 0;

        float dist_origin = 0.0;
        uint  i           = 0;

        while (i < MAX_STEPS
               && dist_origin < CameraUBO.mPerspectiveFar
               && march_data.min_dist > SURF_DIST)
        {
            march_data.min_dist          = FLOAT_MAX;
            march_data.object.shape_type = SHAPE_NONE;
            march_data.object.shape_ind  = 0;

            vec3 point = curr_edge.ray.Origin
                       + curr_edge.ray.Direction * dist_origin;
            march_data  = NextSurface(point);
            dist_origin += march_data.min_dist;
            i++;
        }

        // case a/b: miss
        if (i >= MAX_STEPS || dist_origin >= CameraUBO.mPerspectiveFar) {
            mEdges[curr_edge_ind].ToNode = -1;
            mEdges[curr_edge_ind].Length = dist_origin;
            continue;
        }

        // case c: hit
        vec3 hit_point  = curr_edge.ray.Origin
                        + curr_edge.ray.Direction * dist_origin;
        vec3 hit_normal = CalcNormal(hit_point);

        mEdges[curr_edge_ind].Length = dist_origin;
        mEdges[curr_edge_ind].Normal = hit_normal;

        vec4 surface_color  = GetSurfaceColor(march_data.object);
        uint new_node_ind   = GetNodeIndex();

        mNodes[new_node_ind].ParentEdge   = curr_edge_ind;
        mNodes[new_node_ind].SurfaceColor = surface_color;
        mNodes[new_node_ind].Is2D         = objectIs2D(march_data.object);
        mNodes[new_node_ind].FirstEdge    = -1;

        mEdges[curr_edge_ind].ToNode = int(new_node_ind);

        // translucent: spawn continuation ray
        if (surface_color.w < 1.0) {
            uint new_edge_ind = GetEdgeIndex();

            vec3 nudged_origin = hit_point
                               + curr_edge.ray.Direction * SURF_DIST;
            if (objectIs2D(march_data.object))
                nudged_origin += vec3(THICKNESS_2D);

            mEdges[new_edge_ind].ray.Origin    = nudged_origin;
            mEdges[new_edge_ind].ray.Direction = curr_edge.ray.Direction;
            mEdges[new_edge_ind].Length        = -1.0;
            mEdges[new_edge_ind].Normal        = vec3(0.0);
            mEdges[new_edge_ind].FromNode      = int(new_node_ind);
            mEdges[new_edge_ind].ToNode        = -1;
            mEdges[new_edge_ind].SiblingEdge   = -1;
            mEdges[new_edge_ind].AccumColor    = vec4(0.0);

            mNodes[new_node_ind].FirstEdge = int(new_edge_ind);
            edge_stack[stack_len++]        = int(new_edge_ind);
        }
    }
}

vec4 GenerateColor() {
    vec4 default_color = vec4(0.3, 0.3, 0.3, 1.0);

    for (int i = int(mEdgeCount) - 1; i >= 0; i--) {
        if (mEdges[i].ToNode == -1) {
            mEdges[i].AccumColor = default_color;
            continue;
        }

        Node from_node = mNodes[mEdges[i].FromNode];
        Node to_node   = mNodes[mEdges[i].ToNode];

        vec4 child_color = (to_node.FirstEdge == -1)
                         ? default_color
                         : mEdges[to_node.FirstEdge].AccumColor;

        float surface_alpha  = to_node.SurfaceColor.w;
        vec4  after_surface  = mix(to_node.SurfaceColor, child_color, 1.0 - surface_alpha);

        float medium_alpha       = from_node.SurfaceColor.w;
        mEdges[i].AccumColor     = mix(from_node.SurfaceColor, after_surface, 1.0 - medium_alpha);
    }

    return mEdges[0].AccumColor;
}

// ─── Entry point ─────────────────────────────────────────────────────────────
void main() {
    vec2 frag = gl_FragCoord.xy;

    vec2 uv      = CameraUBO.mRayScale * frag + CameraUBO.mRayOffset;
    vec3 dir     = normalize(vec3(uv.x, uv.y, -1.0));
    vec3 ray_dir = quatRotate(CameraUBO.mRotation, dir);

    // init root node and edge
    mNodeCount = 1;
    mEdgeCount = 1;

    mNodes[0].ParentEdge   = -1;
    mNodes[0].SurfaceColor = vec4(0.0);
    mNodes[0].Is2D         = false;
    mNodes[0].FirstEdge    = -1;

    mEdges[0].ray.Origin    = CameraUBO.mPosition;
    mEdges[0].ray.Direction = ray_dir;
    mEdges[0].FromNode      = 0;
    mEdges[0].SiblingEdge   = -1;
    mEdges[0].ToNode        = -1;
    mEdges[0].Length        = -1.0;
    mEdges[0].AccumColor    = vec4(0.0);

    March();
    oFragColor = GenerateColor();
}
