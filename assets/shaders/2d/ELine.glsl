// Basic Texture Shader

#type vertex
#version 450 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec4 a_Color;

layout(std140, binding = 0) uniform CameraBuffer {
    mat4 u_ViewProjection;
} Camera;


out VS_OUT {
    vec4 Color;
} vs_out;

void main()
{
    vs_out.Color = a_Color;
    gl_Position = Camera.u_ViewProjection * vec4(a_Position, 1.0);
}

#type fragment
#version 450 core

layout(location = 0) out vec4 o_Color;

in VS_OUT {
    vec4 Color;
} fs_in;

void main()
{
    o_Color = fs_in.Color;
}