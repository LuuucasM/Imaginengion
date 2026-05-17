struct ExcludeObject { uint ShapeType; uint ShapeIndex; };
ExcludeObject gExclusions[3];
int gExclusionInd   = 0;
int gExclusionCount = 0;

bool IsExcluded(uint shape_type, uint shape_index) {
    if (gExclusionCount == 0u) return false;
    return (gExclusions[0].ShapeType == shape_type && gExclusions[0].ShapeIndex == shape_index) ||
           (gExclusionCount > 1 && gExclusions[1].ShapeType == shape_type && gExclusions[1].ShapeIndex == shape_index) ||
           (gExclusionCount > 2 && gExclusions[2].ShapeType == shape_type && gExclusions[2].ShapeIndex == shape_index);
}
void ExcludeShape(uint shape_type, uint shape_index) {
    gExclusions[gExclusionInd].ShapeType  = shape_type;
    gExclusions[gExclusionInd].ShapeIndex = shape_index;
    gExclusionInd   = (gExclusionInd + 1) % 3;
    gExclusionCount = min(gExclusionCount + 1, 3);
}

struct DistData { float min_dist; int shape_type; uint shape_index; };

DistData ShortestDistance(vec3 p) {
    float min_dist    = Camera.Data.PerspectiveFar;
    int   shape_type  = SHAPE_NONE;
    uint  shape_index = 0u;

    for (uint i = 0u; i < Camera.Data.QuadsCount; i++) {
        if (IsExcluded(SHAPE_QUAD, i)) continue;
        QuadData data = Quads.data[i];
        float dist = IMQuad(p, data.Position, data.Rotation, data.Scale);
        if (dist < min_dist) { min_dist = dist; shape_type = SHAPE_QUAD; shape_index = i; }
    }
    for (uint i = 0u; i < Camera.Data.GlyphsCount; i++) {
        if (IsExcluded(SHAPE_GLYPH, i)) continue;
        GlyphData data = Glyphs.data[i];
        float dist = IMGlyph(p, data.Position, data.Rotation, data);
        if (dist < min_dist) { min_dist = dist; shape_type = SHAPE_GLYPH; shape_index = i; }
    }
    return DistData(min_dist, shape_type, shape_index);
}

vec4 RayMarch(vec3 ray_origin, vec3 ray_dir) {
    gExclusionCount = 0;
    gExclusionInd   = 0;
    vec3  out_color   = vec3(0.0);
    float out_alpha   = 0.0;
    float dist_origin = 0.0;

    for (uint i = 0u; i < MAX_STEPS; i++) {
        vec3 p = ray_origin + dist_origin * ray_dir;
        DistData next_step = ShortestDistance(p);
        dist_origin += next_step.min_dist;

        if (dist_origin > Camera.Data.PerspectiveFar) {
            float bf = 1.0 - out_alpha;
            out_color += vec3(0.3) * bf;
            out_alpha += bf;
            break;
        }
        if (next_step.min_dist < SURF_DIST) {
            vec4  current_color = GetSurfaceColor(
                ray_origin + dist_origin * ray_dir,
                next_step.shape_type,
                next_step.shape_index
            );
            float bf = current_color.a * (1.0 - out_alpha);
            out_color += current_color.rgb * bf;
            out_alpha += bf;
            if (out_alpha >= 1.0) break;
            ExcludeShape(next_step.shape_type, next_step.shape_index);
        }
    }
    return vec4(out_color, out_alpha);
}
