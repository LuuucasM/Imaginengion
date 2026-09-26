//Tests that need the engine module, run by `zig build test-engine`
test {
    _ = @import("ECS/ECSTests.zig");
    _ = @import("ECSObjects/DeleteTests.zig");
    _ = @import("Physics/TransformPassTests.zig");
    _ = @import("Physics/BodyTagTests.zig");
    _ = @import("Physics/CollisionsTests.zig");
    _ = @import("Physics/RayCastTests.zig");
}

//Core Stuff -----------------------------------
pub const Application = @import("Core/Application.zig");
pub const EngineContext = @import("Core/EngineContext.zig");
pub const Tracy = @import("Core/Tracy.zig");

//Game Object stuff -------------------------------
pub const Entity = @import("ECSObjects/Entity.zig");
pub const EntityComponents = @import("ECSComponents/EComponents.zig");

//Scene Stuff -----------------------------------------
pub const SceneLayer = @import("ECSObjects/Scene.zig");

//Script Stuff ----------------------------------------------
pub const ScriptType = @import("ECSComponents/Asset/ScriptAsset.zig").ScriptType;
pub const _ValidateScript = @import("Scripts/ScriptsProcessor.zig")._ValidateScript;

//Rendering Stuff -------------------------------------------
pub const PushConstants = @import("Renderer/RenderPipeline.zig").PushConstants;
pub const QuatData = @import("Renderer/Renderer2D.zig").QuadData;
pub const GlyphData = @import("Renderer/Renderer2D.zig").GlyphData;
pub const RayMarcher = @import("Renderer/SDFRayMarcher.zig");

//LinAlg stuff
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
