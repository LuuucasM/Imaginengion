#type vertex
#version 460 core

layout(location = 0) in vec2 aPosition;

out vec2 texCoord;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
    texCoord = aPosition * 0.5 + 0.5;
}


#type fragment
#define MAX_STEPS 180
#define MAX_DIST 100.
#define SURF_DIST .00009

//===========================SHAPE DATA===========================
#define SHAPE_QUAD 1.

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

layout (std430, binding = 0) buffer Quads {
     QuadData data[];
};
layout(std140, binding = 0) uniform QuadsCount {
    uint count;
};
//===========================END SHAPE DATA===========================

//===========================Helper Functions===========================
// Quaternion rotation for (w, x, y, z) format
vec3 QuadRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    vec3 uuv = cross(qvec, uv);
    return v + 2.0 * (q.x * uv + uuv);
}

//inverse rotation for (w, x, y, z) format
vec3 QuadRotateInv(vec3 v, vec4 q) {
    return quatRotate(v, vec4(q.x, -q.yzw));
}

vec2 GetTexUVQuad(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = quatRotateInv(hitPoint - translation, rotation);
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

vec4 GetSurfaceColor(vec3 hit_point, float shape_type, int shape_index) {
    vec4 out_color = vec4(0.0, 0.0, 0.0, 0.0);
    if (shape_type == SHAPE_QUAD){
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetTexUVQuad(hit_point, quad.Position, quad.Rotation, quad.Scale);
        if (texture_uv[0] >= 0.0){
            sampler2D tex = sampler2D(quad.TexIndex);
            vec4 texture_color = texture(tex, texture_uv);
            out_color = quad.Color * texture_color;
        }
    }
    return out_color
}
//===========================End Helper Functions===========================

//===========================Primitive SDF Functions===========================
float sdBox( vec3 p, vec3 b )
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
//===========================End Primitive SDF Functions===========================

//===========================IM SDF Functions===========================
float IMQuad( vec3 p, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = quatRotateInv(p - translation, rotation);
    vec3 half_extents = vec3(scale.xy * 0.5, 0.001);
    return sdBox(local_p, half_extents);
}
//===========================End IM SDF Functions===========================

vec3 ShortestDistance(vec3 p){
     vec3 result = (3.402823466e+38, 0.0, 0.0);
     for(int i = 0; i < QuadsCount.count; i++){
          QuadData data = Quads.data[i];
          float dist = IMQuad(p, data.Position, data.Rotation, data.Scale);
          if (dist < result[0]) result = vec3(dist, SHAPE_QUAD, i);
     }
     return result;
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
        vec3 shortest_step = ShortestDistance(p);
        dist_origin += shortest_step[0];

        //we reached the end without seeing anything so we can discard this pixel
        if (dist_origin > MAX_DIST) discard;

        if (shortest_step[0] < SURF_DIST) {
            vec3 hit_point = ray_origin + dist_origin * ray_dir;

            //we have hit a surface so we need to check if this objects alpha is 1.0 or less
            //if its less we need to keep iterating, minus this object, until we reach a combined alpha of 1.0
            vec4 current_color = GetSurfaceColor(hit_point, shortest_step[1], (int)shortest_step[2]);

            float blend_factor = current_color.a * (1.0 - out_alpha);
            out_color += current_color.rgb * blend_factor;
            out_alpha += blend_factor;
            
            if (out_alpha >= 1.0){
                break;
            }

            //add this current object to a list of objects to ignore in shortest distance calculation somehow?
        }
    }
    return out_color;
}

void main() {
    
}