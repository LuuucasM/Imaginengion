#type vertex
#version 460 core

layout(location = 0) in vec2 aPosition;

out vec2 texCoord;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
    texCoord = aPosition * 0.5 + 0.5;
}

#type fragment
#version 460 core

in vec2 texCoord;
out vec4 fragColor;

uniform sampler2D u_Textures[32];
layout(std140, binding = 0) uniform NumTextures {
    uint numLayers;
} Num;

void main() {
    float minDepth = 1.0;
    vec4 finalColor = vec4(0.0);
    
    //for (uint i = 0u; i < Num.numLayers; i++) {
    //    float currentDepth = texture(u_Textures[i + Num.numLayers], texCoord).x;
        
        // Only sample color if depth is closer
    //    if (currentDepth < minDepth) {
    //        minDepth = currentDepth;
    //        finalColor = texture(u_Textures[i], texCoord);
    //    }
    //}
    fragColor = texture(u_Textures[0], texCoord);
}