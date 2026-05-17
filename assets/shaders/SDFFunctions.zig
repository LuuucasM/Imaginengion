const LinAlg = @import("../../src/Imaginengion/Math/LinAlg.zig");
const GlyphData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").GlyphData;

const QUAD_THICKNESS: f32 = 0.001;

pub fn IMQuad(p: @Vector(3, f32), translation: @Vector(3, f32), rotation: @Vector(4, f32), scale: @Vector(3, f32)) f32 {
    return sdBox(
        LinAlg.RotateVec3QuatInv(rotation, p - translation),
        .{ scale[0] * 0.5, scale[1] * 0.5, QUAD_THICKNESS },
    );
}

pub fn IMGlyph(p: @Vector(3, f32), translation: @Vector(3, f32), rotation: @Vector(4, f32), data: GlyphData) f32 {
    return sdGlyph(
        LinAlg.RotateVec3QuatInv(rotation, p - translation),
        data,
    );
}

fn sdBox(p: @Vector(3, f32), b: @Vector(3, f32)) f32 {
    const q = @abs(p) - b;
    return length3(max3(q, .{ 0, 0, 0 })) + @min(@max(q[0], @max(q[1], q[2])), 0.0);
}

fn sdGlyph(p: @Vector(3, f32), data: GlyphData) f32 {
    const left = data.plane_bounds[0];
    const top = data.plane_bounds[1];
    const right = data.plane_bounds[2];
    const bottom = data.plane_bounds[3];

    const plane_size: @Vector(2, f32) = .{
        (right - left) * data.scale,
        (top - bottom) * data.scale,
    };
    const plane_center: @Vector(2, f32) = .{
        (left + right) * 0.5 * data.scale,
        (top + bottom) * 0.5 * data.scale,
    };

    const p2: @Vector(3, f32) = .{
        p[0] - plane_center[0],
        p[1] - plane_center[1],
        p[2],
    };

    return sdBox(p2, .{ plane_size[0] * 0.5, plane_size[1] * 0.5, QUAD_THICKNESS });
}

fn abs3(v: @Vector(3, f32)) @Vector(3, f32) {
    return .{ @abs(v[0]), @abs(v[1]), @abs(v[2]) };
}

fn max3(a: @Vector(3, f32), b: @Vector(3, f32)) @Vector(3, f32) {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };
}

fn length3(v: @Vector(3, f32)) f32 {
    return @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}
