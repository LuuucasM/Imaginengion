const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const CameraRay = @import("CameraRay.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;
const Ray = CameraRay.Ray;

const V3 = Vec3(f32).VectorT;
const inf = std.math.inf(f32);

/// Which face of a box a ray came in through. The order is iq's face index, so @intFromEnum matches it.
pub const BoxFace = enum(u3) {
    NegX,
    PosX,
    NegY,
    PosY,
    NegZ,
    PosZ,
};

pub const HitInfo = struct {
    T: f32, //distance along the ray, in world units since Ray.Dir is normalized. +inf on a miss
    TExit: f32, //where the ray leaves the shape again, the same units as T. +inf on a miss
    Normal: Vec3(f32), //world space, facing back toward the ray
    StartedInside: bool, //the ray origin was inside the shape, T is 0 and Normal is -Dir

    //only RayBox fills these, and only for a hit from outside. UV runs 0 to 1 across the face that
    //was entered, see RayBox for which way
    Face: ?BoxFace = null,
    UV: Vec2(f32) = .{ .x = -1, .y = -1 },

    //+inf rather than -inf so a miss always loses a "closest hit wins" comparison:
    //`if (hit.T < best.T) best = hit;` starting from `best = .miss` needs no special case
    pub const miss: HitInfo = .{
        .T = inf,
        .TExit = inf,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .StartedInside = false,
    };

    pub fn IsHit(self: HitInfo) bool {
        return self.T != inf;
    }
};

/// The nearest of the hits along one ray, each with whatever it was a hit on (Payload): what every caster keeps while
/// it tests shape after shape, whichever shapes it is testing
pub fn NearestHit(comptime Payload: type) type {
    return struct {
        const Self = @This();

        pub const Entry = struct {
            Payload: Payload,
            Hit: HitInfo,
        };

        mBest: ?Entry = null,

        /// Keeps `hit` if it is a hit that counts and nearer than the best so far. A hit past max_t does not count,
        /// and neither does one the ray started inside of when skip_started_inside is set
        pub fn Consider(self: *Self, payload: Payload, hit: HitInfo, max_t: f32, skip_started_inside: bool) void {
            if (!hit.IsHit()) return;
            if (hit.StartedInside and skip_started_inside) return;
            if (hit.T > max_t) return;
            if (self.mBest) |current| {
                if (current.Hit.T <= hit.T) return;
            }
            self.mBest = .{ .Payload = payload, .Hit = hit };
        }
    };
}

const Slabs = struct {
    Enter: f32,
    Exit: f32,
    Near: V3, //per axis, when the ray crosses the nearer of that axis' two walls
};

/// When a local space ray is inside all three pairs of walls of an axis aligned box centered on the
/// origin, or null if that is never ahead of the ray.
fn SlabTest(local_origin: V3, local_dir: V3, half: V3) ?Slabs {
    //an axis the ray is parallel to divides by +-0 and gets +-inf, which makes that slab either
    //never constrain the ray (origin between its walls) or reject it (origin outside them).
    //a ray parallel to and exactly on a wall gives 0 * inf = NaN for that wall, which @min/@max
    //drop in favor of the other operand, so it comes out as a miss and never as a NaN T.
    const inv_dir = @as(V3, @splat(1.0)) / local_dir;
    const t_wall_neg = (-half - local_origin) * inv_dir;
    const t_wall_pos = (half - local_origin) * inv_dir;

    //per axis: when the ray enters and leaves that pair of walls. it is inside the box only while
    //it is inside all three, from the latest enter to the earliest leave
    const t_near = @min(t_wall_neg, t_wall_pos);
    const t_far = @max(t_wall_neg, t_wall_pos);
    const t_enter = @reduce(.Max, t_near);
    const t_exit = @reduce(.Min, t_far);

    if (t_enter > t_exit or t_exit < 0) return null;
    return .{ .Enter = t_enter, .Exit = t_exit, .Near = t_near };
}

/// Ray against an oriented box, using the slab test. A ray that starts inside hits at T = 0,
/// the same as the SDF renderer, which treats a negative distance as an immediate hit.
///
/// A hit from outside also says which face it came through and where on it. UV is 0 to 1 over
/// the face using iq's axes: (y, z) on the X faces, (z, x) on the Y faces and (x, y) on the Z faces.
/// On PosZ that is the same (0, 0) bottom left the quad textures use; faces are not flipped to
/// read the right way round from outside, so the Neg faces come out mirrored.
pub fn RayBox(ray: Ray, center: Vec3(f32), rotation: Quat(f32), half_extents: Vec3(f32)) HitInfo {
    //in the box's own space it is axis aligned and centered on the origin
    const local_origin = ray.Origin.SubVec(center).InvQuatRotate(rotation);
    const local_dir = ray.Dir.InvQuatRotate(rotation);
    var hit = RayBoxLocal(local_origin, local_dir, half_extents);
    if (hit.IsHit()) hit.Normal = hit.Normal.QuatRotate(rotation);
    return hit;
}

/// RayBox with the ray already in the box's own space, where it is axis aligned and centered on the origin: for a
/// caller that has its own way into that space, like the renderer's precomputed shape axes. Everything it returns is
/// in that space too, Normal included. `local_dir` has to be normalized, so T is still in world units
pub fn RayBoxLocal(local_origin_vec: Vec3(f32), local_dir_vec: Vec3(f32), half_extents: Vec3(f32)) HitInfo {
    const local_origin = local_origin_vec.ToVector();
    const local_dir = local_dir_vec.ToVector();
    const half = half_extents.ToVector();

    const slabs = SlabTest(local_origin, local_dir, half) orelse return .miss;

    if (slabs.Enter < 0) {
        return .{ .T = 0, .TExit = slabs.Exit, .Normal = local_dir_vec.Neg(), .StartedInside = true };
    }

    //the face that was entered through belongs to the axis whose enter time is the box's.
    //a parallel axis can't match, its enter time is +-inf and t_enter is finite here. an exact
    //edge or corner hit matches several axes, and normalizing blends their faces into the
    //edge's normal
    const zero: V3 = @splat(0.0);
    const facing_back = @select(f32, local_dir > zero, @as(V3, @splat(-1.0)), @as(V3, @splat(1.0)));
    const entered_axis = slabs.Near == @as(V3, @splat(slabs.Enter));
    const local_normal = @select(f32, entered_axis, facing_back, zero);

    //Face and UV have to be one face though, so an edge or corner hit takes the first of its axes
    //arrays, since a vector can't be indexed by a runtime axis
    const axis: u2 = if (entered_axis[0]) 0 else if (entered_axis[1]) 1 else 2;
    const facing_back_arr: [3]f32 = facing_back;
    const face: BoxFace = @enumFromInt(@as(u3, axis) * 2 + @intFromBool(facing_back_arr[axis] > 0));

    const local_point: [3]f32 = local_origin + local_dir * @as(V3, @splat(slabs.Enter));
    const half_arr: [3]f32 = half;
    const u_axis = (@as(u3, axis) + 1) % 3;
    const v_axis = (@as(u3, axis) + 2) % 3;
    const uv = Vec2(f32){
        .x = std.math.clamp((local_point[u_axis] + half_arr[u_axis]) / (2.0 * half_arr[u_axis]), 0.0, 1.0),
        .y = std.math.clamp((local_point[v_axis] + half_arr[v_axis]) / (2.0 * half_arr[v_axis]), 0.0, 1.0),
    };

    return .{
        .T = slabs.Enter,
        .TExit = slabs.Exit,
        .Normal = Vec3(f32).FromVector(local_normal).Dir(),
        .StartedInside = false,
        .Face = face,
        .UV = uv,
    };
}

/// Ray against an oriented box with its edges and corners rounded off by `radius` (iq's
/// roundedboxIntersect and roundedboxNormal). `half_extents` is the whole shape, the same as RayBox's,
/// and the rounding cuts into it rather than growing past it, so radius can be at most the smallest
/// half extent. Face and UV are left empty, a hit on a rounded edge has no single face.
pub fn RayRoundedBox(ray: Ray, center: Vec3(f32), rotation: Quat(f32), half_extents: Vec3(f32), radius: f32) HitInfo {
    std.debug.assert(radius >= 0 and radius <= @reduce(.Min, half_extents.ToVector()));

    //no rounding leaves nothing for the edge and corner tests to hit, only the exact edge itself
    if (radius == 0) return RayBox(ray, center, rotation, half_extents);

    const local_origin = ray.Origin.SubVec(center).InvQuatRotate(rotation).ToVector();
    const local_dir = ray.Dir.InvQuatRotate(rotation).ToVector();
    const inner = half_extents.ToVector() - @as(V3, @splat(radius));

    //the rounded box fits inside the plain one, so missing that misses it
    const bounds = SlabTest(local_origin, local_dir, half_extents.ToVector()) orelse return .miss;

    //it's convex, so where the ray leaves is where the same ray fired back from the far side of
    //the bounds first touches it
    const far_point = local_origin + local_dir * @as(V3, @splat(bounds.Exit));
    const back = RoundedBoxEntry(far_point, -local_dir, inner, radius);

    if (sdRoundedBoxLocal(local_origin, inner, radius) <= 0) {
        const t_exit = if (back == inf) 0 else bounds.Exit - back;
        return .{ .T = 0, .TExit = t_exit, .Normal = ray.Dir.Neg(), .StartedInside = true };
    }

    const t = RoundedBoxEntry(local_origin, local_dir, inner, radius);
    if (t == inf) return .miss;

    //straight out from the nearest point on the inner box, the same for flat faces and rounded edges
    const local_point = local_origin + local_dir * @as(V3, @splat(t));
    const outward = Vec3(f32).FromVector(@max(@abs(local_point) - inner, @as(V3, @splat(0.0)))).Dir().ToVector();
    const local_normal = @select(f32, local_point < @as(V3, @splat(0.0)), -outward, outward);

    return .{
        .T = t,
        //float error on a grazing hit can leave the reverse ray just missing
        .TExit = if (back == inf) t else bounds.Exit - back,
        .Normal = Vec3(f32).FromVector(local_normal).QuatRotate(rotation),
        .StartedInside = false,
    };
}

fn sdRoundedBoxLocal(point: V3, inner: V3, radius: f32) f32 {
    const q = @abs(point) - inner;
    const outside = Vec3(f32).FromVector(@max(q, @as(V3, @splat(0.0)))).Len();
    return outside + @min(@reduce(.Max, q), 0.0) - radius;
}

/// Where a local space ray first touches an axis aligned rounded box centered on the origin, +inf if
/// never. `inner` is the box the rounding is swept around. The ray has to start outside the shape.
fn RoundedBoxEntry(local_origin: V3, local_dir: V3, inner: V3, radius: f32) f32 {
    const bounds = SlabTest(local_origin, local_dir, inner + @as(V3, @splat(radius))) orelse return inf;
    const t_start = @max(bounds.Enter, 0.0);

    //reaching the bounds on one of the flat faces is the hit. iq tests which axes are past the inner
    //box, but that splits a point right where a face meets an edge by one float bit either way, and
    //the reverse ray for the exit starts on exactly such points. counted as beside the edge, it only
    //finds that edge's cylinder behind it and the other side's ahead, inside the shape. so it's by
    //distance instead, with a margin for the float error in landing on the bounds
    const pos = local_origin + local_dir * @as(V3, @splat(t_start));
    const on_surface = 0.00001 * (1.0 + @reduce(.Max, @abs(pos)));
    if (sdRoundedBoxLocal(pos, inner, radius) <= on_surface) return t_start;

    //otherwise it's in the gap the rounding cut away beside an edge or corner, and the hit is on a
    //corner sphere or edge cylinder. iq's version mirrors into the octant the ray enters in and only
    //tries that corner and its three edges, but a ray that enters beside an edge can run along it
    //and over into the next octant, most easily when the inner box is thin next to the radius (the
    //sphere tracing test found one). so this tries all 8 corners and 12 edges: the rounded box is
    //their union with the flat faces, so the nearest of them is the hit.
    const dd = local_dir * local_dir;
    const ra2 = radius * radius;

    var t = inf;

    //corners: a sphere around each of the inner box's corners. the origin is outside all of
    //them, so the nearer root is the one ahead if either is
    const a_corner = @reduce(.Add, dd);
    for (0..8) |corner| {
        const signs = V3{
            if (corner & 1 != 0) -1.0 else 1.0,
            if (corner & 2 != 0) -1.0 else 1.0,
            if (corner & 4 != 0) -1.0 else 1.0,
        };
        const oc = local_origin - inner * signs;
        const b = @reduce(.Add, oc * local_dir);
        const c = @reduce(.Add, oc * oc) - ra2;
        const h = b * b - a_corner * c;
        if (h > 0) {
            const t_corner = (-b - @sqrt(h)) / a_corner;
            if (t_corner >= 0 and t_corner < t) t = t_corner;
        }
    }

    //edges: a cylinder along each of the inner box's edges, only as long as that edge. its ends are
    //the corner spheres, so a ray starting inside the endless cylinder past the end is covered by those
    inline for (0..3) |along| {
        const j = (along + 1) % 3;
        const k = (along + 2) % 3;
        //parallel to the edge: never meets the cylinder's side
        const a = dd[j] + dd[k];
        if (a > 0) {
            for (0..4) |edge| {
                const oj = local_origin[j] - inner[j] * @as(f32, if (edge & 1 != 0) -1.0 else 1.0);
                const ok = local_origin[k] - inner[k] * @as(f32, if (edge & 2 != 0) -1.0 else 1.0);
                const b = oj * local_dir[j] + ok * local_dir[k];
                const c = oj * oj + ok * ok - ra2;
                const h = b * b - a * c;
                if (h > 0) {
                    const t_edge = (-b - @sqrt(h)) / a;
                    if (t_edge >= 0 and t_edge < t and @abs(local_origin[along] + local_dir[along] * t_edge) < inner[along]) t = t_edge;
                }
            }
        }
    }

    return t;
}

/// Ray against an oriented plate with rounded corners: a 2D rounded box in the xy plane, extruded along
/// z. half_extents is laid out like a quad's, xy the box and z half the thickness. `radii` rounds each
/// corner on its own, in iq's order (x top right, y bottom right, z top left, w bottom left), each at
/// most the smaller of half_extents.x and .y; the same radius four times rounds them all alike.
///
/// Unlike RayRoundedBox this only rounds in xy, so the thickness doesn't limit the radius, which is
/// what rounded quads need. A hit on the front or back fills Face (PosZ / NegZ) and UV the same as
/// RayBox; a hit on the thin side leaves them empty.
pub fn RayRoundedBox2D(ray: Ray, center: Vec3(f32), rotation: Quat(f32), half_extents: Vec3(f32), radii: Vec4(f32)) HitInfo {
    const local_origin = ray.Origin.SubVec(center).InvQuatRotate(rotation);
    const local_dir = ray.Dir.InvQuatRotate(rotation);
    var hit = RayRoundedBox2DLocal(local_origin, local_dir, half_extents, radii);
    if (hit.IsHit()) hit.Normal = hit.Normal.QuatRotate(rotation);
    return hit;
}

/// RayRoundedBox2D with the ray already in the plate's own space, the same as RayBoxLocal: everything it returns is
/// in that space too, Normal included, and `local_dir` has to be normalized
pub fn RayRoundedBox2DLocal(local_origin: Vec3(f32), local_dir: Vec3(f32), half_extents: Vec3(f32), radii: Vec4(f32)) HitInfo {
    //square corners leave nothing to round, so it's the plain box, without the corner circles. Only its sides differ:
    //here a hit on one has no Face, the same as on the rounded path
    if (radii.x == 0 and radii.y == 0 and radii.z == 0 and radii.w == 0) {
        var hit = RayBoxLocal(local_origin, local_dir, half_extents);
        if (hit.Face) |face| {
            if (face != .PosZ and face != .NegZ) {
                hit.Face = null;
                hit.UV = .{ .x = -1, .y = -1 };
            }
        }
        return hit;
    }

    const origin_2d = Vec2(f32){ .x = local_origin.x, .y = local_origin.y };
    const dir_2d = Vec2(f32){ .x = local_dir.x, .y = local_dir.y };
    const half_2d = Vec2(f32){ .x = half_extents.x, .y = half_extents.y };

    //it's where the ray is both between the front and back and inside the 2D shape. both are
    //convex, so each is one span of the line and the plate is where they overlap
    const span_z = LineSpan(local_origin.z, local_dir.z, half_extents.z) orelse return .miss;
    const span_2d = RoundedBox2DSpan(origin_2d, dir_2d, half_2d, radii) orelse return .miss;
    const enter = @max(span_z.Enter, span_2d.Enter);
    const exit = @min(span_z.Exit, span_2d.Exit);

    if (enter > exit or exit < 0) return .miss;

    if (enter < 0) {
        return .{ .T = 0, .TExit = exit, .Normal = local_dir.Neg(), .StartedInside = true };
    }

    const local_point = local_origin.AddVec(local_dir.MulScalar(enter));

    //the later of the two entries is the surface it came through
    if (span_z.Enter >= span_2d.Enter) {
        const front = local_dir.z < 0;
        return .{
            .T = enter,
            .TExit = exit,
            .Normal = .{ .x = 0, .y = 0, .z = if (front) 1.0 else -1.0 },
            .StartedInside = false,
            .Face = if (front) .PosZ else .NegZ,
            .UV = .{
                .x = std.math.clamp((local_point.x + half_extents.x) / (2.0 * half_extents.x), 0.0, 1.0),
                .y = std.math.clamp((local_point.y + half_extents.y) / (2.0 * half_extents.y), 0.0, 1.0),
            },
        };
    }

    const side = NormalRoundedBox2DLocal(.{ .x = local_point.x, .y = local_point.y }, half_2d, radii);
    return .{
        .T = enter,
        .TExit = exit,
        .Normal = .{ .x = side.x, .y = side.y, .z = 0 },
        .StartedInside = false,
    };
}

/// The span of a whole line, forward and back, that is inside something.
pub const Span = struct {
    Enter: f32,
    Exit: f32,
};

/// The part of a ray inside an axis aligned box (min to max): from where it enters to where it leaves, in the ray's
/// own distance units. Enter is negative for a ray that starts inside. Null when the ray never is, or only behind
/// its origin. `inv_dir` is 1 / the ray's direction per axis, worked out once per ray by the caller, since a BVH walk
/// tests one ray against many boxes. The same slab test as SlabTest, so a direction parallel to an axis works the
/// same way: its slab either never limits the ray or rules it out
pub fn RayAabb(origin: Vec3(f32), inv_dir: Vec3(f32), min: Vec3(f32), max: Vec3(f32)) ?Span {
    const o = origin.ToVector();
    const inv = inv_dir.ToVector();
    const t_min = (min.ToVector() - o) * inv;
    const t_max = (max.ToVector() - o) * inv;
    const enter = @reduce(.Max, @min(t_min, t_max));
    const exit = @reduce(.Min, @max(t_min, t_max));
    if (enter > exit or exit < 0) return null;
    return .{ .Enter = enter, .Exit = exit };
}

/// When a line along one axis is between -half and half. Parallel to it is always or never.
fn LineSpan(origin: f32, dir: f32, half: f32) ?Span {
    if (dir == 0) {
        return if (@abs(origin) <= half) .{ .Enter = -inf, .Exit = inf } else null;
    }
    const t_neg = (-half - origin) / dir;
    const t_pos = (half - origin) / dir;
    return .{ .Enter = @min(t_neg, t_pos), .Exit = @max(t_neg, t_pos) };
}

/// When a 2D line is inside a rounded box centered on the origin.
fn RoundedBox2DSpan(origin: Vec2(f32), dir: Vec2(f32), half: Vec2(f32), radii: Vec4(f32)) ?Span {
    //straight along z: it's at the one spot the whole time
    if (dir.x == 0 and dir.y == 0) {
        return if (sdRoundedBox2DLocal(origin, half, radii) <= 0) .{ .Enter = -inf, .Exit = inf } else null;
    }

    //through the plain box first. it can't have both axes parallel, so both ends are finite
    const span_x = LineSpan(origin.x, dir.x, half.x) orelse return null;
    const span_y = LineSpan(origin.y, dir.y, half.y) orelse return null;
    const box_enter = @max(span_x.Enter, span_y.Enter);
    const box_exit = @min(span_x.Exit, span_y.Exit);
    if (box_enter > box_exit) return null;

    return .{
        .Enter = CornerCrossing(origin, dir, box_enter, half, radii, .Enter) orelse return null,
        .Exit = CornerCrossing(origin, dir, box_exit, half, radii, .Exit) orelse return null,
    };
}

/// Where a line really crosses into or out of a 2D rounded box, given `t` where it crosses the plain
/// box's edge. On a straight side that's `t` itself. Otherwise it's in a gap one corner's rounding cut
/// away, which is walled in by that corner's arc and the plain box's edge, so the only way on into the
/// shape is through that arc. The arc's whole circle is inside the shape, so its nearer root is where
/// the line comes in, and the farther where it goes out.
fn CornerCrossing(origin: Vec2(f32), dir: Vec2(f32), t: f32, half: Vec2(f32), radii: Vec4(f32), which: enum { Enter, Exit }) ?f32 {
    const point = origin.AddVec(dir.MulScalar(t));

    //by distance, with a margin for the float error in landing on the box's edge, rather than which
    //axes are past the corner, for the same reason as RoundedBoxEntry
    const on_surface = 0.00001 * (1.0 + @max(@abs(point.x), @abs(point.y)));
    if (sdRoundedBox2DLocal(point, half, radii) <= on_surface) return t;

    const r = CornerRadius2D(point, radii);
    const corner = Vec2(f32){
        .x = if (point.x < 0) -(half.x - r) else half.x - r,
        .y = if (point.y < 0) -(half.y - r) else half.y - r,
    };
    const oc = origin.SubVec(corner);
    const a = dir.Dot(dir);
    const b = oc.Dot(dir);
    const c = oc.Dot(oc) - r * r;
    const h = b * b - a * c;
    if (h <= 0) return null;

    return switch (which) {
        .Enter => (-b - @sqrt(h)) / a,
        .Exit => (-b + @sqrt(h)) / a,
    };
}

//mirror SDFFunctions' 2D rounded box, which can't be imported here since it pulls in the renderer

fn CornerRadius2D(point: Vec2(f32), radii: Vec4(f32)) f32 {
    if (point.x > 0) {
        return if (point.y > 0) radii.x else radii.y;
    }
    return if (point.y > 0) radii.z else radii.w;
}

fn sdRoundedBox2DLocal(point: Vec2(f32), half: Vec2(f32), radii: Vec4(f32)) f32 {
    const r = CornerRadius2D(point, radii);
    const qx = @abs(point.x) - half.x + r;
    const qy = @abs(point.y) - half.y + r;
    const outside = (Vec2(f32){ .x = @max(qx, 0), .y = @max(qy, 0) }).Len();
    return @min(@max(qx, qy), 0) + outside - r;
}

fn NormalRoundedBox2DLocal(point: Vec2(f32), half: Vec2(f32), radii: Vec4(f32)) Vec2(f32) {
    const r = CornerRadius2D(point, radii);
    const wx = @abs(point.x) - half.x + r;
    const wy = @abs(point.y) - half.y + r;
    const g = @max(wx, wy);

    const grad = if (g > 0) (Vec2(f32){ .x = @max(wx, 0), .y = @max(wy, 0) }).Dir() else (Vec2(f32){
        .x = if (wx == g) 1.0 else 0.0,
        .y = if (wy == g) 1.0 else 0.0,
    }).Dir();

    return .{
        .x = if (point.x < 0) -grad.x else grad.x,
        .y = if (point.y < 0) -grad.y else grad.y,
    };
}

/// Ray against a sphere. Ray.Dir must be normalized, which CameraRay.MakeRay guarantees.
pub fn RaySphere(ray: Ray, center: Vec3(f32), radius: f32) HitInfo {
    if (radius <= 0) return .miss;

    //|origin + t*dir - center|^2 = radius^2 is a quadratic in t: t^2 + 2bt + c = 0
    const to_origin = ray.Origin.SubVec(center);
    const b = to_origin.Dot(ray.Dir);
    const c = to_origin.Dot(to_origin) - radius * radius;

    if (c < 0) {
        //inside, so the discriminant can't be negative and the far root is ahead
        return .{ .T = 0, .TExit = -b + @sqrt(b * b - c), .Normal = ray.Dir.Neg(), .StartedInside = true };
    }

    //outside and pointing away
    if (b > 0) return .miss;

    const discriminant = b * b - c;
    if (discriminant < 0) return .miss;

    const t = -b - @sqrt(discriminant);
    const point = ray.Origin.AddVec(ray.Dir.MulScalar(t));

    return .{
        .T = t,
        .TExit = -b + @sqrt(discriminant),
        .Normal = point.SubVec(center).DivScalar(radius),
        .StartedInside = false,
    };
}
