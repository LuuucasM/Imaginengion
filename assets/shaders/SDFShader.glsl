#type vertex
#version 460 core

layout(location = 0) in vec2 aPosition;


void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
}


#type fragment
#version 460
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require

#define MAX_STEPS 128
#define SURF_DIST 0.00099
#define QUAD_THICKNESS 0.001

layout(location = 0) out vec4 oFragColor;

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

//===========================Shape Data===========================
#define SHAPE_NONE 0
#define SHAPE_QUAD 1

struct QuadData {
    vec3 Position;
    vec4 Rotation;
    vec3 Scale;
    vec4 Color;
    vec2 TexCoordTop;
    vec2 TexCoordBottom;
    float TilingFactor;
    uint64_t TexIndex;
};

layout (std430, binding = 2) buffer QuadsSSBO {
     QuadData data[];
} Quads;

layout(std140, binding = 3) uniform QuadsCountUBO {
    uint count;
} QuadsCount;
//===========================End Shape Data===========================

//===========================Helper Functions/Data===========================
struct ExcludeObject {
    uint ShapeType;
    uint ShapeIndex;
};

// Ring buffer for recent exclusions
ExcludeObject gExclusions[3];
int gExclusionInd = 0;
int gExclusionCount = 0;

vec3 QuadRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    return v + 2.0 * q.x * uv + 2.0 * cross(qvec, uv);
}

//inverse rotation for (w, x, y, z) format
vec3 QuadRotateInv(vec3 v, vec4 q) {
    return QuadRotate(v, vec4(q.x, -q.y, -q.z, -q.w));
}

vec2 GetTexUVQuad(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuadRotateInv(hit_point - translation, rotation);
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

vec4 GetSurfaceColor(vec3 hit_point, int shape_type, uint shape_index) {
    if (shape_type == SHAPE_QUAD){
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetTexUVQuad(hit_point, quad.Position, quad.Rotation, quad.Scale);

        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0){
            // Apply tiling factor to UV coordinates
            vec2 tiled_uv = texture_uv * quad.TilingFactor;
            
            sampler2D tex = sampler2D(quad.TexIndex);
            vec4 texture_color = texture(tex, tiled_uv);
            return (quad.Color * texture_color);
        }
    }
    return vec4(0.0);
}

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
//===========================End Helper Functions/Data===========================

//===========================Primitive SDF Functions===========================
float sdBox( vec3 p, vec3 b )
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
//===========================End Primitive SDF Functions===========================

//===========================IM SDF Functions===========================
float IMQuad( vec3 p, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuadRotateInv(p - translation, rotation);
    vec3 half_extents = vec3(scale.xy * 0.5, QUAD_THICKNESS);
    return sdBox(local_p, half_extents);
}
//===========================End IM SDF Functions===========================

struct DistData {
    float min_dist;
    int shape_type;
    uint shape_index;
};

DistData ShortestDistance(vec3 p){
    float min_dist = 3.402823466e+38;
    int shape_type = SHAPE_NONE;
    uint shape_index = 0;

    //for quads
    for(uint i = 0u; i < QuadsCount.count; i++){
        if (IsExcluded(SHAPE_QUAD, i)) continue;

            QuadData data = Quads.data[i];
            float dist = IMQuad(p, data.Position, data.Rotation, data.Scale);

            if (dist < min_dist) {
                min_dist = dist;
                shape_type = SHAPE_QUAD;
                shape_index = i;
            };
        if (min_dist < SURF_DIST) return DistData(min_dist, shape_type, shape_index);
    }

    //for future shapes

    return DistData(min_dist, shape_type, shape_index);
}

vec4 RayMarch(vec3 ray_origin, vec3 ray_dir) {
    vec3 out_color = vec3(0.0);
    float out_alpha = 0.0;
    float dist_origin = 0.0;

    for (uint i = 0u; i < MAX_STEPS; i++){
        vec3 p = ray_origin + dist_origin * ray_dir;
        DistData next_step = ShortestDistance(p);
        dist_origin += next_step.min_dist;

        if (dist_origin > Camera.data.PerspectiveFar){
            float blend_factor = 1.0 * (1.0 - out_alpha); //1.0 is the background alpha 
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
    vec3 ray_dir = QuadRotate(base_ray_dir, Camera.data.Rotation);

    oFragColor = RayMarch(Camera.data.Position, ray_dir);
}
