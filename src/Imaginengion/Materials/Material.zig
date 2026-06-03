const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const Material = @This();

//for surfaces
mSurfaceColor: Vec4(f32),

//for volumes
Absorption: Vec3(f32),
