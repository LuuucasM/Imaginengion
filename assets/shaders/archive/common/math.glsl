vec3 QuatRotate(vec3 v, vec4 q) {
    vec3 qvec = q.yzw;
    vec3 uv = cross(qvec, v);
    return v + 2.0 * q.x * uv + 2.0 * cross(qvec, uv);
}
vec3 QuatRotateInv(vec3 v, vec4 q) {
    return QuatRotate(v, vec4(q.x, -q.y, -q.z, -q.w));
}
float Median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}