const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const Material = @This();

//for surfaces
mSurfaceColor: Vec4(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },

//for volumes
Absorption: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
