float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdGlyph(vec3 p, GlyphData data) {
    float left   = data.PlaneBounds.x;
    float top    = data.PlaneBounds.y;
    float right  = data.PlaneBounds.z;
    float bottom = data.PlaneBounds.w;
    vec2 plane_size   = vec2(right - left, top - bottom) * data.Scale;
    vec2 plane_center = vec2((left + right) * 0.5, (top + bottom) * 0.5) * data.Scale;
    p.xy -= plane_center;
    return sdBox(p, vec3(plane_size * 0.5, QUAD_THICKNESS));
}

float IMQuad(vec3 p, vec3 translation, vec4 rotation, vec3 scale) {
    return sdBox(QuatRotateInv(p - translation, rotation), vec3(scale.xy * 0.5, QUAD_THICKNESS));
}
float IMGlyph(vec3 p, vec3 translation, vec4 rotation, GlyphData data) {
    return sdGlyph(QuatRotateInv(p - translation, rotation), data);
}
