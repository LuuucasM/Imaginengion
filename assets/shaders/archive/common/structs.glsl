struct CameraData {
    vec4 Rotation;
    vec3 Position;
    float PerspectiveFar;
    vec2 RayScale;
    vec2 RayOffset;
    uint  QuadsCount;
    uint  GlyphsCount;
};

struct QuadData {
    vec3  Position;
    vec4  Rotation;
    vec3  Scale;
    float TilingFactor;
    vec4  Color;
    vec4  TexCoords; 
    uint  TextureHandle;
};

struct GlyphData {
    vec3  Position;
    float Scale;
    vec4  Rotation;
    float TilingFactor;
    vec4  Color;
    vec4  TexCoords;
    vec4  AtlasBounds;
    vec4  PlaneBounds;
    // Replaces: AtlasIndex: uint, TexIndex: uint
    uint AtlasHandle;
    uint TextureHandle;
};