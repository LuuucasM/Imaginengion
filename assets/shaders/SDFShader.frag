#version 460 core
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require

#define MAX_STEPS 512
#define SURF_DIST 0.00099

layout(location = 0) out vec4 oFragColor;

//===========================LinAlg===========================
vec3 QuatRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    return v + 2.0 * q.x * uv + 2.0 * cross(qvec, uv);
}
//inverse rotation for (w, x, y, z) format
vec3 QuatRotateInv(vec3 v, vec4 q) {
    return QuatRotate(v, vec4(q.x, -q.y, -q.z, -q.w)); //format is (w, x, y, z) even tho opengl does (x, y, z, w)
}

float Median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}
//===========================End LinAlg=======================

//===========================Camera===========================
struct CameraData {
    vec4 Rotation;        // 16 bytes ← 16-byte boundary
    vec3 Position;        // 12 bytes
    float PerspectiveFar; // 4 bytes  ← 16-byte boundary
    float ResolutionWidth;  // 4 bytes
    float ResolutionHeight; // 4 bytes
    float AspectRatio;      // 4 bytes
    float FOV; // 4 bytes  ← 16-byte boundary
};

struct ModeData{
    uint mode;
};

layout(std140, binding = 0) uniform CameraUBO {
    CameraData data;
} Camera;

layout(std140, binding = 1) uniform ModeUBO {
    ModeData data;
} Mode;
//===========================End Camera===========================

//=======================Exclusion ring buffer===============
struct ExcludeObject {
    uint ShapeType;
    uint ShapeIndex;
};

// Ring buffer for recent exclusions
ExcludeObject gExclusions[3];
int gExclusionInd = 0;
int gExclusionCount = 0;

bool IsExcluded(uint shape_type, uint shape_index) {
    if (gExclusionCount == 0u) return false;

    return (gExclusions[0].ShapeType == shape_type && gExclusions[0].ShapeIndex == shape_index) ||
           (gExclusionCount > 1 && gExclusions[1].ShapeType == shape_type && gExclusions[1].ShapeIndex == shape_index) ||
           (gExclusionCount > 2 && gExclusions[2].ShapeType == shape_type && gExclusions[2].ShapeIndex == shape_index);
}

void ExcludeShape(uint shape_type, uint shape_index) {
    gExclusions[gExclusionInd].ShapeType = shape_type;
    gExclusions[gExclusionInd].ShapeIndex = shape_index;

    gExclusionInd = (gExclusionInd + 1) % 3;
    gExclusionCount = min (gExclusionCount + 1, 3);
}
//=======================End Exclusion ring buffer=============

//===========================Shape Data===========================
#define SHAPE_NONE 0
#define SHAPE_QUAD 1
#define SHAPE_GLYPH 2

//========quads=========
#define QUAD_THICKNESS 0.001
struct QuadData {
    vec3 Position;
    vec4 Rotation;
    vec3 Scale;
    
    float TilingFactor;
    vec4 Color;
    vec4 TexCoords;

    uint64_t TexIndex;
};
layout (std430, binding = 0) buffer QuadsSSBO {
     QuadData data[];
} Quads;
layout(std140, binding = 2) uniform QuadsCountUBO {
    uint count;
} QuadsCount;
//======end quads======

//======glyphs========
struct GlyphData {
    vec3 Position;
    float Scale;
    vec4 Rotation;

    float TilingFactor;
    vec4 Color;
    vec4 TexCoords;

    vec4 AtlasBounds;
    vec4 PlaneBounds;
    uint64_t AtlasIndex;
    uint64_t TexIndex;
};
layout (std430, binding = 1) buffer GlyphSSBO {
     GlyphData data[];
} Glyphs;
layout(std140, binding = 3) uniform GlyphCountUBO {
    uint count;
} GlyphsCount;
//======end glyphs======


//===========================End Shape Data===========================

//===========================Pixel Color functions====================
vec2 GetQuadUV(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuatRotateInv(hit_point - translation, rotation);
    vec2 half_extents_xy = scale.xy * 0.5;
    
    // Check if we're on the front face (+Z) - using constant instead of calculating
    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        vec2 uv = (local_p.xy + half_extents_xy) / (2.0 * half_extents_xy);
        // Combined bounds check
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) {
            return uv;
        }
    }
    return vec2(-1.0); // Invalid UV
}

vec2 GetTextUV(vec3 hit_point, GlyphData glyph){
    vec3 local_p = QuatRotateInv(hit_point - glyph.Position, glyph.Rotation);

    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        // Extract bounds: [left, top, right, bottom]
        float left = glyph.PlaneBounds.x;
        float top = glyph.PlaneBounds.y;
        float right = glyph.PlaneBounds.z;
        float bottom = glyph.PlaneBounds.w;
        
        // Apply centering offset
        vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * glyph.Scale;
        local_p.xy -= plane_center;
        
        // Calculate size
        vec2 plane_size = vec2(right - left, top - bottom) * glyph.Scale;
        
        // UV calculation: map from centered space back to [0,1]
        vec2 uv = (local_p.xy + plane_size * 0.5) / plane_size;
        
        // Flip V coordinate since texture space is typically bottom-up but plane is top-down
        uv.y = 1.0 - uv.y;
        
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) {
            return uv;
        }
    }
    return vec2(-1.0);
}

float GetMSD(vec2 texture_uv, GlyphData glyph){
    sampler2D atlas_tex = sampler2D(glyph.AtlasIndex);
    vec2 atlas_size = vec2(textureSize(atlas_tex, 0));

    vec2 atlas_min = glyph.AtlasBounds.xy / atlas_size;
    vec2 atlas_max = glyph.AtlasBounds.zw / atlas_size;

    // Map UV to atlas bounds
    vec2 atlas_uv = mix(atlas_min, atlas_max, texture_uv);
    
    vec3 msd = texture(atlas_tex, atlas_uv).rgb;
    
    // Get median signed distance
    return Median(msd.r, msd.g, msd.b);
}

vec4 GetSurfaceColor(vec3 hit_point, int shape_type, uint shape_index) {
    if (shape_type == SHAPE_QUAD){
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetQuadUV(hit_point, quad.Position, quad.Rotation, quad.Scale);

        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0){
            // Apply tiling factor to UV coordinates
            vec2 tiled_uv = texture_uv * quad.TilingFactor;
            
            // Remap UV coordinates from quad local space to texture atlas space
            vec2 atlas_uv = mix(quad.TexCoords.xy, quad.TexCoords.zw, tiled_uv);
            
            sampler2D tex = sampler2D(quad.TexIndex);
            vec4 texture_color = texture(tex, atlas_uv);
            return (quad.Color * texture_color);
        }
    }
    if (shape_type == SHAPE_GLYPH){
        //return vec4(1.0, 0.0, 0.0, 1.0);
        GlyphData glyph = Glyphs.data[shape_index];
        vec2 texture_uv = GetTextUV(hit_point, glyph);

        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0){
            float msd = GetMSD(texture_uv, glyph);

            if (msd >= 0.5){
                float alpha = smoothstep(0.4, 0.6, msd);

                vec2 tiled_uv = texture_uv * glyph.TilingFactor;

                vec2 atlas_uv = mix(glyph.TexCoords.xy, glyph.TexCoords.zw, tiled_uv);

                sampler2D tex = sampler2D(glyph.TexIndex);

                vec4 texture_color = texture(tex, atlas_uv);

                return (vec4(glyph.Color.rgb, alpha * glyph.Color.a) * texture_color);
            }
        }
    }
    return vec4(0.0);
}
//===========================End Pixel Color Functions================

//===========================Primitive SDF Functions===========================
float sdBox( vec3 p, vec3 b ) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdGlyph(vec3 p, GlyphData glyph){
    float left = glyph.PlaneBounds.x;
    float top = glyph.PlaneBounds.y;
    float right = glyph.PlaneBounds.z;
    float bottom = glyph.PlaneBounds.w;
    
    vec2 plane_size = vec2(right - left, top - bottom) * glyph.Scale;
    
    vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * glyph.Scale;
    
    // Offset to center
    p.xy -= plane_center;
    
    vec3 half_extents = vec3(plane_size * 0.5, QUAD_THICKNESS);

    return sdBox(p, half_extents);
}
//===========================End Primitive SDF Functions===========================

//===========================IM SDF Functions===========================
float IMQuad( vec3 p, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuatRotateInv(p - translation, rotation);
    vec3 half_extents = vec3(scale.xy * 0.5, QUAD_THICKNESS);
    return sdBox(local_p, half_extents);
}

float IMGlyph(vec3 p, GlyphData glyph){
    vec3 local_p = QuatRotateInv(p - glyph.Position, glyph.Rotation);
    return sdGlyph(local_p, glyph);
}
//===========================End IM SDF Functions===========================

//===========================RAY MARCHING===================================
struct DistData {
    float min_dist;
    int shape_type;
    uint shape_index;
};
DistData ShortestDistance(vec3 p){
    float min_dist = Camera.data.PerspectiveFar;
    int shape_type = SHAPE_NONE;
    uint shape_index = 0;

    //=========for quads===========
    for(uint i = 0u; i < QuadsCount.count; i++){
        if (IsExcluded(SHAPE_QUAD, i)) continue;

            QuadData data = Quads.data[i];
            float dist = IMQuad(p, data.Position, data.Rotation, data.Scale);

            if (dist < min_dist) {
                min_dist = dist;
                shape_type = SHAPE_QUAD;
                shape_index = i;
            };
    }
    //========end for quads============

    //=======for glyphs==============
    for(uint i = 0u; i < GlyphsCount.count; i++){
        if (IsExcluded(SHAPE_GLYPH, i)) continue;

        GlyphData glyph = Glyphs.data[i];
        float dist = IMGlyph(p, glyph);
        
        if (dist < min_dist) {
                min_dist = dist;
                shape_type = SHAPE_GLYPH;
                shape_index = i;
            };
    }
    //======end for glyphs===============

    return DistData(min_dist, shape_type, shape_index);
}
vec4 RayMarch(vec3 ray_origin, vec3 ray_dir) {
    gExclusionCount = 0;
    gExclusionInd = 0;
    vec3 out_color = vec3(0.0);
    float out_alpha = 0.0;
    float dist_origin = 0.0;

    for (uint i = 0u; i < MAX_STEPS; i++){
        vec3 p = ray_origin + dist_origin * ray_dir;
        DistData next_step = ShortestDistance(p);
        dist_origin += next_step.min_dist;

        if (dist_origin > Camera.data.PerspectiveFar){
            float blend_factor = 1.0 * (1.0 - out_alpha); //the first 1.0 is the background alpha which is just 1.0
            out_color += vec3(0.3, 0.3, 0.3) * blend_factor; //vec3(0.3, 0.3, 0.3) is the background color
            out_alpha += blend_factor;
            break;
        }

        if (next_step.min_dist < SURF_DIST) {
            vec3 hit_point = ray_origin + dist_origin * ray_dir;
            vec4 current_color = GetSurfaceColor(hit_point, next_step.shape_type, next_step.shape_index);

            float blend_factor = current_color.a * (1.0 - out_alpha);
            out_color += current_color.rgb * blend_factor;
            out_alpha += blend_factor;
            
            if (out_alpha >= 1.0) break;

            ExcludeShape(next_step.shape_type, next_step.shape_index);
        }
    }
    return vec4(out_color, out_alpha);
}
//===========================END RAY MARCHING===================================

void main() {
    // Center gl_FragCoord.xy so that (0,0) is the center of the screen
    vec2 centered = gl_FragCoord.xy - 0.5 * vec2(Camera.data.ResolutionWidth, Camera.data.ResolutionHeight);

    // Normalize to [-1, 1] range
    vec2 uv = centered / (0.5 * vec2(Camera.data.ResolutionWidth, Camera.data.ResolutionHeight));

    // Conditionally apply aspect ratio correction if bit 0 of Mode.data.mode is set
    if ((Mode.data.mode & 1u) != 0u) {
        uv.x *= Camera.data.AspectRatio; // <-- Aspect ratio correction
    }
    uv.y = -uv.y; // Flip y axis if needed

    float tan_half_fov = tan(Camera.data.FOV * 0.5);

    vec3 base_ray_dir = normalize(vec3(uv * tan_half_fov, -1.0));
    vec3 ray_dir = QuatRotate(base_ray_dir, Camera.data.Rotation);

    oFragColor = RayMarch(Camera.data.Position, ray_dir);
}
