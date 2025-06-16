#type vertex
#version 460 core

layout(location = 0) in vec2 aPosition;


void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
}


#type fragment
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require

#define MAX_STEPS 180
#define SURF_DIST .000099

out vec4 oFragColor;

//===========================Camera===========================
struct CameraData {
    vec3 Position;
    vec4 Rotation;
    float PerspectiveFar;
};

layout(std140, binding = 0) uniform Camera {
    CameraData data;
};

layout(std140, binding = 1) uniform Resolution {
    vec3 data;
};

//===========================End Camera===========================

//===========================Shape Data===========================
#define SHAPE_NONE 0
#define SHAPE_QUAD 1

struct QuadData {
    vec3 Position;
    vec4 Rotation;
    vec3 Scale;
    vec4 Color;
    uint64_t TexIndex;
    vec2 TexCoordTop;
    vec2 TexCoordBottom;
    float TilingFactor;
};

layout (std430, binding = 2) buffer Quads {
     QuadData data[];
};

layout(std140, binding = 3) uniform QuadsCount {
    uint count;
};
//===========================End Shape Data===========================

//===========================Helper Functions/Data===========================
struct ExcludeObject {
    int ShapeType;
    int ShapeIndex;
};

// Ring buffer for recent exclusions
ExcludeObject gExclusions[3];
int gExclusionInd = 0;
int gExclusionCount = 0;

// Quaternion rotation for (w, x, y, z) format
vec3 QuadRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    vec3 uuv = cross(qvec, uv);
    return v + 2.0 * (q.x * uv + uuv);
}

//inverse rotation for (w, x, y, z) format
vec3 QuadRotateInv(vec3 v, vec4 q) {
    return QuadRotate(v, vec4(q.x, -q.yzw));
}

vec2 GetTexUVQuad(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuadRotateInv(hit_point - translation, rotation);
    vec3 half_extents = vec3(scale.xy * 0.5, 0.001);
    
    // Check if we're on the front face (+Z)
    if (abs(local_p.z - half_extents.z) < 0.001) {
        vec2 uv = (local_p.xy + half_extents.xy) / (2.0 * half_extents.xy);
        // Return UV only if within bounds
        if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
            return uv;
        }
    }
    return vec2(-1.0); // Invalid UV
}

vec4 GetSurfaceColor(vec3 hit_point, int shape_type, int shape_index) {
    vec4 out_color = vec4(0.0, 0.0, 0.0, 0.0);
    if (shape_type == SHAPE_QUAD){
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetTexUVQuad(hit_point, quad.Position, quad.Rotation, quad.Scale);
        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0){
            sampler2D tex = sampler2D(quad.TexIndex);
            vec4 texture_color = texture(tex, texture_uv);
            out_color = quad.Color * texture_color;
        }
    }
    return out_color;
}

bool IsExcluded(int shape_type, int shape_index) {
    if (gExclusionCount == 0) return false;

    if (gExclusions[0].ShapeType == shape_type && gExclusions[0].ShapeIndex == shape_index) return true;
    if (gExclusionCount > 1 && gExclusions[1].ShapeType == shape_type && gExclusions[1].ShapeIndex == shape_index) return true;
    if (gExclusionCount > 2 && gExclusions[2].ShapeType == shape_type && gExclusions[2].ShapeIndex == shape_index) return true;
    
    return false;
}

void ExcludeShape(int shape_type, int shape_index) {
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
    vec3 half_extents = vec3(scale.xy * 0.5, 0.001);
    return sdBox(local_p, half_extents);
}
//===========================End IM SDF Functions===========================

struct DistData {
    float min_dist;
    int shape_type;
    int shape_index;
};

DistData ShortestDistance(vec3 p){
    float min_dist = 3.402823466e+38;
    int shape_type = SHAPE_NONE;
    int shape_index = 0;

    //for quads
    for(int i = 0; i < QuadsCount.count; i++){
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

    
    for (int i = 0; i < MAX_STEPS; i++){
        vec3 p = ray_origin + dist_origin * ray_dir;
        
        //note shortest_step.x = the actual shortest distance
        //shortest_step.y = what shape it using the #define SHAPE_X
        //shortest_step.z = the index in the specific array
        DistData next_step = ShortestDistance(p);
        dist_origin += next_step.min_dist;

        //we reached the end without seeing anything so we can discard this pixel
        if (dist_origin > Camera.data.PerspectiveFar) break;

        if (next_step.min_dist < SURF_DIST) {
            vec3 hit_point = ray_origin + dist_origin * ray_dir;

            //we have hit a surface so we need to check if this objects alpha is 1.0 or less
            //if its less we need to keep iterating, minus this object, until we reach a combined alpha of 1.0
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
    //calculate ray direction using camera rotation
    vec3 camera_pos = Camera.data.Position;
    vec4 camera_rot = Camera.data.Rotation;

    vec2 uv = (gl_FragCoord.xy - Resolution.data.xy * 0.5) / Resolution.data.y;

    vec3 base_ray_dir = normalize(vec3(uv, -1.0));
    vec3 ray_dir = QuadRotate(base_ray_dir, camera_rot);

    oFragColor = RayMarch(camera_pos, ray_dir);
}