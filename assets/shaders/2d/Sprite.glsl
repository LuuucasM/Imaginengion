// Basic Texture Shader

#type vertex
#version 460 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec4 a_Color;
layout(location = 2) in vec2 a_TexCoord;
layout(location = 3) in float a_TexIndex;
layout(location = 4) in float a_TilingFactor;

layout(std140, binding = 0) uniform CameraBuffer {
    mat4 u_ViewProjection;
} Camera;

out VS_OUT {
    vec4 Color;
    vec2 TexCoord;
    float TilingFactor;
    flat float TexIndex;
} vs_out;

void main()
{
    vs_out.Color = a_Color;
    vs_out.TexCoord = a_TexCoord;
    vs_out.TilingFactor = a_TilingFactor;
    vs_out.TexIndex = a_TexIndex;
	//gl_Position = Camera.u_ViewProjection * vec4(a_Position, 1.0);
    gl_Position = vec4(a_Position, 1.0);
}

#type fragment
#version 460 core

layout(location = 0) out vec4 o_Color;

in VS_OUT {
    vec4 Color;
    vec2 TexCoord;
    float TilingFactor;
    flat float TexIndex;
} fs_in;

uniform sampler2D u_Textures[32];

void main()
{
    vec4 texColor = fs_in.Color;
    int texIndex = int(fs_in.TexIndex);
    
    //texColor *= texture(u_Textures[texIndex], fs_in.TexCoord * fs_in.TilingFactor);
    
    //o_Color = texColor;
    o_Color = vec4(1.0, 0.0, 0.0, 1.0);
}