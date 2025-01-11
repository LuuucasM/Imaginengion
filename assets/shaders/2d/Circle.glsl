// Renderer2D Circle Shader

#type vertex
#version 460 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_LocalPosition;
layout(location = 2) in vec4 a_Color;
layout(location = 3) in float a_Thickness;
layout(location = 4) in float a_Fade;

layout(std140, binding = 0) uniform CameraBuffer {
    mat4 u_ViewProjection;
} Camera;

out VS_OUT {
    vec3 LocalPosition;
    vec4 Color;
    float Thickness;
    float Fade;
} vs_out;

void main()
{
    vs_out.LocalPosition = a_LocalPosition;
    vs_out.Color = a_Color;
    vs_out.Thickness = a_Thickness;
    vs_out.Fade = a_Fade;
    vs_out.EntityID = a_EntityID;

    gl_Position = Camera.u_ViewProjection * vec4(a_Position, 1.0);
}

#type fragment
#version 460 core

layout(location = 0) out vec4 o_color;

in VS_OUT {
    vec3 LocalPosition;
    vec4 Color;
    float Thickness;
    float Fade;
} fs_in;

void main()
{
    float distance = 1.0 - length(fs_in.LocalPosition);
    float colorAlpha = smoothstep(0.0, fs_in.Fade, distance);
    colorAlpha *= smoothstep(fs_in.Thickness + fs_in.Fade, fs_in.Thickness, distance);

    if (colorAlpha == 0.0) {
        discard;
    }

    o_Color = fs_in.Color;
    o_Color.a *= colorAlpha;
}