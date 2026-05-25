//Rendering Stuff -------------------------------------------
pub const PushConstants = @import("Renderer/RenderPipeline.zig").PushConstants;
pub const QuatData = @import("Renderer/Renderer2D.zig").QuadData;
pub const GlyphData = @import("Renderer/Renderer2D.zig").GlyphData;
pub const RayMarcher = @import("Renderer/SDFRayMarcher.zig");

//LinAlg stuff-------------------------------------
const MathTypes = @import("Math/MathTypes.zig");
pub const MathUtils = @import("Math/MathUtils.zig");
pub const Vec2 = MathTypes.Vec2;
pub const Vec3 = MathTypes.Vec3;
pub const Vec4 = MathTypes.Vec4;
pub const Mat3 = MathTypes.Mat3;
pub const Mat4 = MathTypes.Mat4;
pub const Quat = MathTypes.Quat;
