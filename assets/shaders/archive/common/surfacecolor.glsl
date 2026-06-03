vec3 AtlasUV(vec2 tex_uv, vec2 uv_offset, vec2 uv_scale, uint layer) {
    // Map tex_uv [0,1] into the texture's region within the layer
    vec2 atlas_uv = uv_offset + tex_uv * uv_scale;
    return vec3(atlas_uv, float(layer));
}

vec2 GetQuadUV(vec3 hit_point, vec3 translation, vec4 rotation, vec3 scale) {
    vec3 local_p = QuatRotateInv(hit_point - translation, rotation);
    vec2 half_extents_xy = scale.xy * 0.5;
    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        vec2 uv = (local_p.xy + half_extents_xy) / (2.0 * half_extents_xy);
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) return uv;
    }
    return vec2(-1.0);
}

vec2 GetTextUV(vec3 hit_point, GlyphData glyph) {
    vec3 local_p = QuatRotateInv(hit_point - glyph.Position, glyph.Rotation);
    if (abs(local_p.z - QUAD_THICKNESS) < QUAD_THICKNESS) {
        float left   = glyph.PlaneBounds.x;
        float top    = glyph.PlaneBounds.y;
        float right  = glyph.PlaneBounds.z;
        float bottom = glyph.PlaneBounds.w;
        vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * glyph.Scale;
        local_p.xy -= plane_center;
        vec2 plane_size = vec2(right - left, top - bottom) * glyph.Scale;
        vec2 uv = (local_p.xy + plane_size * 0.5) / plane_size;
        uv.y = 1.0 - uv.y;
        if (all(bvec4(greaterThanEqual(uv, vec2(0.0)), lessThanEqual(uv, vec2(1.0))))) return uv;
    }
    return vec2(-1.0);
}

float GetMSD(vec2 texture_uv, GlyphData glyph) {
    // Sample the MSDF atlas — remap texture_uv into the atlas bounds region
    // AtlasBounds is in texels within the atlas layer, convert to [0,1]
    vec2 atlas_size = vec2(textureSize(uTextures, 0).xy);
    vec2 atlas_min  = glyph.AtlasBounds.xy / atlas_size;
    vec2 atlas_max  = glyph.AtlasBounds.zw / atlas_size;
    vec2 raw_uv     = mix(atlas_min, atlas_max, texture_uv);

    // Remap into atlas layer space
    vec3 sample_uv = AtlasUV(raw_uv, glyph.AtlasUVOffset, glyph.AtlasUVScale, glyph.AtlasLayer);
    vec3 msd = texture(uTextures, sample_uv).rgb;
    return Median(msd.r, msd.g, msd.b);
}

vec4 GetSurfaceColor(vec3 hit_point, int shape_type, uint shape_index) {
    return vec4(1.0, 0.0, 0.0, 1.0);
    if (shape_type == SHAPE_QUAD) {
        QuadData quad = Quads.data[shape_index];
        vec2 texture_uv = GetQuadUV(hit_point, quad.Position, quad.Rotation, quad.Scale);
        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0) {
            // Apply tiling/crop from TexCoords, then remap into atlas layer
            vec2 tiled_uv  = texture_uv * quad.TilingFactor;
            vec2 cropped_uv = mix(quad.TexCoords.xy, quad.TexCoords.zw, tiled_uv);
            vec3 atlas_uv  = AtlasUV(cropped_uv, quad.TexUVOffset, quad.TexUVScale, quad.TexLayer);
            return quad.Color * texture(uTextures, atlas_uv);
        }
    }
    if (shape_type == SHAPE_GLYPH) {
        GlyphData glyph = Glyphs.data[shape_index];
        vec2 texture_uv = GetTextUV(hit_point, glyph);
        if (texture_uv[0] >= 0.0 && texture_uv[1] >= 0.0) {
            float msd = GetMSD(texture_uv, glyph);
            if (msd >= 0.5) {
                float alpha    = smoothstep(0.4, 0.6, msd);
                vec2 tiled_uv  = texture_uv * glyph.TilingFactor;
                vec2 cropped_uv = mix(glyph.TexCoords.xy, glyph.TexCoords.zw, tiled_uv);
                vec3 atlas_uv  = AtlasUV(cropped_uv, glyph.TexUVOffset, glyph.TexUVScale, glyph.TexLayer);
                vec4 tex_color = texture(uTextures, atlas_uv);
                return vec4(glyph.Color.rgb, alpha * glyph.Color.a) * tex_color;
            }
        }
    }
    //return vec4(0.0);
}