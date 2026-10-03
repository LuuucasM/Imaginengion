//Tests that need the engine module, run by `zig build test-engine`
test {
    _ = @import("Tests/ECS/ECSTests.zig");
    _ = @import("Tests/ECSObjects/DeleteTests.zig");
    _ = @import("Tests/Serializer/SerializerTests.zig");
    _ = @import("Tests/ECSComponents/Asset/ObjectAssetTests.zig");
    _ = @import("Tests/ECSObjects/TmplTests.zig");
    _ = @import("Tests/ECSObjects/LayerTagTests.zig");
    _ = @import("Tests/ECSObjects/OverlayTests.zig");
    _ = @import("Tests/Physics/TransformPassTests.zig");
    _ = @import("Tests/Physics/BodyTagTests.zig");
    _ = @import("Tests/Physics/CollisionsTests.zig");
    _ = @import("Tests/Physics/SolverTests.zig");
    _ = @import("Tests/Physics/RayCastTests.zig");
    _ = @import("Tests/Physics/PhysicsQueriesTests.zig");
    _ = @import("Tests/Math/SDFFunctionsTests.zig");
    _ = @import("Tests/Renderer/ViewShapesTests.zig");
    _ = @import("Tests/UI/LayoutComponentTests.zig");
    _ = @import("Tests/UI/LayoutSystemTests.zig");
    _ = @import("Tests/Pointer/PointerSystemTests.zig");
    _ = @import("Tests/UI/FocusSystemTests.zig");
    _ = @import("Tests/UI/PopupSystemTests.zig");
    _ = @import("Tests/UI/ScrollSystemTests.zig");
    _ = @import("Tests/UI/UIElementTests.zig");
    _ = @import("Tests/UI/StyleSystemTests.zig");
    _ = @import("Tests/Scripts/EventScriptsTests.zig");
    _ = @import("Tests/UI/WidgetsTests.zig");
    _ = @import("Tests/Core/WorldCopyTests.zig");
    _ = @import("Tests/AudioManager/BusSaveTests.zig");
}

//Core Stuff -----------------------------------
pub const Application = @import("Core/Application.zig");
pub const EngineContext = @import("Core/EngineContext.zig");
pub const Tracy = @import("Core/Tracy.zig");

//Game Object stuff -------------------------------
pub const Entity = @import("ECSObjects/Entity.zig");
pub const EntityComponents = @import("ECSComponents/EComponents.zig");

//Audio Stuff -----------------------------------------
pub const Voice = @import("ECSObjects/Voice.zig");
pub const Bus = @import("ECSObjects/Bus.zig");

//Scene Stuff -----------------------------------------
pub const SceneLayer = @import("ECSObjects/Scene.zig");

//Script Stuff ----------------------------------------------
pub const ScriptType = @import("ECSComponents/Asset/ScriptAsset.zig").ScriptType;
pub const ScriptResult = @import("ECSComponents/Asset/ScriptAsset.zig").ScriptResult;
pub const _ValidateScript = @import("Scripts/ScriptsProcessor.zig")._ValidateScript;

//Event Stuff -----------------------------------------------
pub const KeyboardPressedEvent = @import("Events/WindowEventData.zig").KeyboardPressedEvent;
pub const PointerEvent = @import("Events/PointerEventData.zig").EventT;
pub const PointerEventData = @import("Events/PointerEventData.zig");
pub const UIEvent = @import("Events/UIEventData.zig").EventT;
pub const UIEventData = @import("Events/UIEventData.zig");

//UI Stuff --------------------------------------------------
pub const UIManager = @import("UI/UIManager.zig");
pub const UIElement = @import("ECSObjects/UIElement.zig");
pub const UIComponents = @import("ECSComponents/UIComponents.zig");
pub const WidgetActions = @import("UI/WidgetActions.zig");
pub const Widgets = @import("UI/Widgets.zig");

//Physics Stuff ---------------------------------------------
pub const CollisionInfo = @import("Physics/Collisions.zig").CollisionInfo;
pub const PreSolveInfo = @import("Physics/Collisions.zig").PreSolveInfo;
pub const PhysicsQueries = @import("Physics/PhysicsQueries.zig");

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
