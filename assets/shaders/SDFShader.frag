#version 460
#extension GL_EXT_nonuniform_qualifier : require

#define MAX_STEPS      512
#define SURF_DIST      0.00099
#define QUAD_THICKNESS 0.001

layout(location = 0) out vec4 oFragColor;

layout(set = 0, binding = 0) uniform sampler2D uTextures[];

#define SHAPE_NONE  0
#define SHAPE_QUAD  1
#define SHAPE_GLYPH 2

struct QuadData {
    vec3  Position;
    vec4  Rotation;
    vec3  Scale;
    float TilingFactor;
    vec4  Color;
    vec4  TexCoords;
    uint  TexIndex;     // index into uTextures[]
};
layout(set = 1, binding = 0) readonly buffer QuadsSSBO {
    QuadData data[];
} Quads;

struct GlyphData {
    vec3  Position;
    float Scale;
    vec4  Rotation;
    float TilingFactor;
    vec4  Color;
    vec4  TexCoords;
    vec4  AtlasBounds;
    vec4  PlaneBounds;
    uint  AtlasIndex;   // index into uTextures[]
    uint  TexIndex;     // index into uTextures[]
};
layout(set = 1, binding = 1) readonly buffer GlyphSSBO {
    GlyphData data[];
} Glyphs;

layout(push_constant) uniform PushConstants {
    vec4  Rotation;
    vec3  Position;
    float PerspectiveFar;
    float ResolutionWidth;
    float ResolutionHeight;
    float AspectRatio;
    float FOV;
    uint  Mode;
    uint  QuadsCount;
    uint  GlyphsCount;
} Camera;

// =============================================================================
// LinAlg
// =============================================================================
vec3 QuatRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    return v + 2.0 * q.x * uv + 2.0 * cross(qvec, uv);
}
vec3 QuatRotateInv(vec3 v, vec4 q) {
    return QuatRotate(v, vec4(q.x, -q.y, -q.z, -q.w));
}
float Median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

// =============================================================================
// Exclusion ring buffer
// =============================================================================
struct ExcludeObject { uint ShapeType; uint ShapeIndex; };
ExcludeObject gExclusions[3];
int gExclusionInd   = 0;
int gExclusionCount = 0;

bool IsExcluded(uint shape_type, uint shape_index) {
    if (gExclusionCount == 0u) return false;
    return (gExclusions[0].ShapeType == shape_type && gExclusions[0].ShapeIndex == shape_index) ||
           (gExclusionCount > 1 && gExclusions[1].ShapeType == shape_type && gExclusions[1].ShapeIndex == shape_index) ||
           (gExclusionCount > 2 && gExclusions[2].ShapeType == shape_type && gExclusions[2].ShapeIndex == shape_index);
}
void ExcludeShape(uint shape_type, uint shape_index) {
    gExclusions[gExclusionInd].ShapeType  = shape_type;
    gExclusions[gExclusionInd].ShapeIndex = shape_index;
    gExclusionInd   = (gExclusionInd + 1) % 3;
    gExclusionCount = min(gExclusionCount + 1, 3);
}

// =============================================================================
// Pixel color functions
// =============================================================================
vec2 GetQuadUV(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuatRotateInv(hit_point - translation, rotation);
    vec2 half_extents_xy = scale.xy * 0.5;
    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        vec2 uv = (local_p.xy + half_extents_xy) / (2.0 * half_extents_xy);
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) return uv;
    }
    return vec2(-1.0);
}

vec2 GetTextUV(vec3 hit_point, GlyphData glyph) {
    vec3 local_p = QuatRotateInv(hit_point - glyph.Position, glyph.Rotation);
    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        float left   = glyph.PlaneBounds.x;
        float top    = glyph.PlaneBounds.y;
        float right  = glyph.PlaneBounds.z;
        float bottom = glyph.PlaneBounds.w;
        vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * glyph.Scale;
        local_p.xy -= plane_center;
        vec2 plane_size = vec2(right - left, top - bottom) * glyph.Scale;
        vec2 uv = (local_p.xy + plane_size * 0.5) / plane_size;
        uv.y = 1.0 - uv.y;
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) return uv;
    }
    return vec2(-1.0);
}

float GetMSD(vec2 texture_uv, GlyphData glyph) {
    vec2 atlas_size = vec2(textureSize(uTextures[nonuniformEXT(glyph.AtlasIndex)], 0));
    vec2 atlas_min  = glyph.AtlasBounds.xy / atlas_size;
    vec2 atlas_max  = glyph.AtlasBounds.zw / atlas_size;
    vec2 atlas_uv   = mix(atlas_min, atlas_max, texture_uv);
    vec3 msd = texture(uTextures[nonuniformEXT(glyph.AtlasIndex)], atlas_uv).rgb;
    return Median(msd.r, msd.g, msd.b);
}

vec4 GetSurfaceColor(vec3 hit_point, int shape_type, uint shape_index) {
    if (shape_type == SHAPE_QUAD) {
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetQuadUV(hit_point, quad.Position, quad.Rotation, quad.Scale);
        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0) {
            vec2 tiled_uv = texture_uv * quad.TilingFactor;
            vec2 atlas_uv = mix(quad.TexCoords.xy, quad.TexCoords.zw, tiled_uv);
            return quad.Color * texture(uTextures[nonuniformEXT(quad.TexIndex)], atlas_uv);
        }
    }
    if (shape_type == SHAPE_GLYPH) {
        GlyphData glyph = Glyphs.data[shape_index];
        vec2 texture_uv = GetTextUV(hit_point, glyph);
        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0) {
            float msd = GetMSD(texture_uv, glyph);
            if (msd >= 0.5) {
                float alpha    = smoothstep(0.4, 0.6, msd);
                vec2 tiled_uv  = texture_uv * glyph.TilingFactor;
                vec2 atlas_uv  = mix(glyph.TexCoords.xy, glyph.TexCoords.zw, tiled_uv);
                vec4 tex_color = texture(uTextures[nonuniformEXT(glyph.TexIndex)], atlas_uv);
                return vec4(glyph.Color.rgb, alpha * glyph.Color.a) * tex_color;
            }
        }
    }
    return vec4(0.0);
}

// =============================================================================
// SDF primitives
// =============================================================================
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdGlyph(vec3 p, GlyphData glyph) {
    float left   = glyph.PlaneBounds.x;
    float top    = glyph.PlaneBounds.y;
    float right  = glyph.PlaneBounds.z;
    float bottom = glyph.PlaneBounds.w;
    vec2 plane_size   = vec2(right - left, top - bottom) * glyph.Scale;
    vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * glyph.Scale;
    p.xy -= plane_center;
    return sdBox(p, vec3(plane_size * 0.5, QUAD_THICKNESS));
}
float IMQuad(vec3 p, vec3 translation, vec4 rotation, vec3 scale) {
    return sdBox(QuatRotateInv(p - translation, rotation), vec3(scale.xy * 0.5, QUAD_THICKNESS));
}
float IMGlyph(vec3 p, GlyphData glyph) {
    return sdGlyph(QuatRotateInv(p - glyph.Position, glyph.Rotation), glyph);
}

// =============================================================================
// Ray marching
// =============================================================================
struct DistData { float min_dist; int shape_type; uint shape_index; };

DistData ShortestDistance(vec3 p) {
    float min_dist    = Camera.PerspectiveFar;
    int   shape_type  = SHAPE_NONE;
    uint  shape_index = 0u;

    for (uint i = 0u; i < Camera.QuadsCount; i++) {
        if (IsExcluded(SHAPE_QUAD, i)) continue;
        QuadData data = Quads.data[i];
        float dist = IMQuad(p, data.Position, data.Rotation, data.Scale);
        if (dist < min_dist) { min_dist = dist; shape_type = SHAPE_QUAD; shape_index = i; }
    }
    for (uint i = 0u; i < Camera.GlyphsCount; i++) {
        if (IsExcluded(SHAPE_GLYPH, i)) continue;
        GlyphData glyph = Glyphs.data[i];
        float dist = IMGlyph(p, glyph);
        if (dist < min_dist) { min_dist = dist; shape_type = SHAPE_GLYPH; shape_index = i; }
    }
    return DistData(min_dist, shape_type, shape_index);
}

vec4 RayMarch(vec3 ray_origin, vec3 ray_dir) {
    gExclusionCount = 0;
    gExclusionInd   = 0;
    vec3  out_color   = vec3(0.0);
    float out_alpha   = 0.0;
    float dist_origin = 0.0;

    for (uint i = 0u; i < MAX_STEPS; i++) {
        vec3     p         = ray_origin + dist_origin * ray_dir;
        DistData next_step = ShortestDistance(p);
        dist_origin += next_step.min_dist;

        if (dist_origin > Camera.PerspectiveFar) {
            float bf = 1.0 - out_alpha;
            out_color += vec3(0.3) * bf;
            out_alpha += bf;
            break;
        }
        if (next_step.min_dist < SURF_DIST) {
            vec4  current_color = GetSurfaceColor(
                ray_origin + dist_origin * ray_dir,
                next_step.shape_type,
                next_step.shape_index
            );
            float bf = current_color.a * (1.0 - out_alpha);
            out_color += current_color.rgb * bf;
            out_alpha += bf;
            if (out_alpha >= 1.0) break;
            ExcludeShape(next_step.shape_type, next_step.shape_index);
        }
    }
    return vec4(out_color, out_alpha);
}

// =============================================================================
// Main
// =============================================================================
void main() {
    vec2 centered = gl_FragCoord.xy - 0.5 * vec2(Camera.ResolutionWidth, Camera.ResolutionHeight);
    vec2 uv = centered / (0.5 * vec2(Camera.ResolutionWidth, Camera.ResolutionHeight));

    if ((Camera.Mode & 1u) != 0u) uv.x *= Camera.AspectRatio;
    uv.y = -uv.y;

    float tan_half_fov = tan(Camera.FOV * 0.5);
    vec3 base_ray_dir  = normalize(vec3(uv * tan_half_fov, -1.0));
    vec3 ray_dir       = QuatRotate(base_ray_dir, Camera.Rotation);

    oFragColor = RayMarch(Camera.Position, ray_dir);
}
