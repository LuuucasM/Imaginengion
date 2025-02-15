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

layout(binding = 0) uniform sampler2D u_Textures[32];
layout(std140, binding = 0) uniform NumTextures {
    uint numLayers;
} Num;

void main() {
    float minDepth = 1.0;
    float currentDepth = minDepth;
    vec4 finalColor = vec4(0.0);
    
    for (uint i = 0u; i < Num.numLayers; i++) {
        currentDepth = texture(u_Textures[i + Num.numLayers], texCoord).x;
        
        // Only sample color if depth is closer
        if (currentDepth < minDepth) {
            minDepth = currentDepth;
            finalColor = texture(u_Textures[i], texCoord);
        }
    }

    if (currentDepth == 1.0){
        discard;
    }

    fragColor = finalColor;
}