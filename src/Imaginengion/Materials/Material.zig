const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const EngineContext = @import("../Core/EngineContext.zig");

pub const OpaqueMode = enum {
    Opaque,
    Transparent,
};

//for surfaces
mSurfaceColor: Vec4(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },

//for volumes
Absorption: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },

//Render options
mOpaqueMode: OpaqueMode = .Opaque,
