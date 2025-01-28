// Vertex Shader
#type vertex
#version 460 core

layout(location = 0) in vec2 aPosition;

out vec2 texCoord;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
    texCoord = aPosition * 0.5 + 0.5;
}

// Fragment Shader
#type fragment
#version 460 core

in vec2 texCoord;
out vec4 fragColor;

// Uniforms for textures
uniform sampler2D u_ColorTextures[16];  // Array for color textures
uniform sampler2D u_DepthTextures[16];  // Separate array for depth textures
layout(std140, binding = 0) uniform NumTextures {
    uint numLayers;  // Number of layers to process
} Num;

void main() {
    // Initialize with maximum depth and transparent color
    float minDepth = 1.0;
    vec4 finalColor = vec4(0.0);
    
    // Loop through all layers
    for (uint i = 0u; i < Num.numLayers; i++) {
        // Sample depth first for early rejection
        float currentDepth = texture(u_DepthTextures[i], texCoord).r;
        
        // Only sample color if depth is closer
        if (currentDepth < minDepth) {
            minDepth = currentDepth;
            finalColor = texture(u_ColorTextures[i], texCoord);
        }
    }
    
    // Discard fully transparent pixels
    if (finalColor.a < 0.001) {
        discard;
    }
    
    fragColor = finalColor;
}