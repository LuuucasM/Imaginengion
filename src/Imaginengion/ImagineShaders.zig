//Rendering Stuff -------------------------------------------
pub const PushConstants = @import("Renderer/RenderPipeline.zig").SDFPushConstants;
pub const ShapeData = @import("Renderer/Renderer2D.zig").ShapeData;
pub const ShapeSurface = @import("Renderer/Renderer2D.zig").ShapeSurface;
pub const BVHNode = @import("Core/BVH.zig").Node;
pub const ClipData = @import("Renderer/Renderer2D.zig").ClipData;
pub const SurfShadingData = @import("Renderer/Renderer.zig").SurfShadingData;
pub const MedShadingData = @import("Renderer/Renderer.zig").MedShadingData;
pub const RayMarcher = @import("Renderer/SDFRayMarcher.zig").RayMarcher;
pub const Node = @import("Renderer/SDFRayMarcher.zig").Node;
pub const Edge = @import("Renderer/SDFRayMarcher.zig").Edge;

//LinAlg stuff-------------------------------------
const MathTypes = @import("Math/MathTypes.zig");
pub const MathUtils = @import("Math/MathUtils.zig");
pub const CameraRay = @import("Math/CameraRay.zig");
pub const RayIntersect = @import("Math/RayIntersect.zig");
pub const Vec2 = MathTypes.Vec2;
pub const Vec3 = MathTypes.Vec3;
pub const Vec4 = MathTypes.Vec4;
pub const Mat3 = MathTypes.Mat3;
pub const Mat4 = MathTypes.Mat4;
pub const Quat = MathTypes.Quat;
