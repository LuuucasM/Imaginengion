//Tests that need the engine module, run by `zig build test-engine`
test {
    _ = @import("Tests/ECS/ECSTests.zig");
    _ = @import("Tests/ECS/SystemsLayerTests.zig");
    _ = @import("Tests/ECSObjects/DeleteTests.zig");
    _ = @import("Tests/Serializer/SerializerTests.zig");
    _ = @import("Tests/ECSComponents/Asset/ObjectAssetTests.zig");
    _ = @import("Tests/ECSComponents/Asset/PendingDeleteTests.zig");
    _ = @import("Tests/ECSComponents/Asset/LoadFailedTagTests.zig");
    _ = @import("Tests/ECSComponents/Asset/EnumAssetTests.zig");
    _ = @import("Tests/ECSComponents/EnumComponentTests.zig");
    _ = @import("Tests/ECSComponents/RenderTargetTests.zig");
    _ = @import("Tests/ECSObjects/TmplTests.zig");
    _ = @import("Tests/ECSObjects/LayerTagTests.zig");
    _ = @import("Tests/ECSObjects/OverlayTests.zig");
    _ = @import("Tests/ECSObjects/GetWorldTests.zig");
    _ = @import("Tests/ECSObjects/LoadOrGetTests.zig");
    _ = @import("Tests/ECSObjects/ComponentAddedTests.zig");
    _ = @import("Tests/Physics/TransformPassTests.zig");
    _ = @import("Tests/Physics/BodyTagTests.zig");
    _ = @import("Tests/Physics/CollisionsTests.zig");
    _ = @import("Tests/Physics/SolverTests.zig");
    _ = @import("Tests/Physics/BroadPhaseTests.zig");
    _ = @import("Tests/Physics/PauseTests.zig");
    _ = @import("Tests/Physics/RayCastTests.zig");
    _ = @import("Tests/Physics/PhysicsQueriesTests.zig");
    _ = @import("Tests/Physics/CollisionLayersTests.zig");
    _ = @import("Tests/Physics/CollisionMaskTests.zig");
    _ = @import("Tests/Math/SDFFunctionsTests.zig");
    _ = @import("Tests/Renderer/ViewShapesTests.zig");
    _ = @import("Tests/Renderer/WorldRenderTests.zig");
    _ = @import("Tests/Renderer/RayMarcherTests.zig");
    _ = @import("Tests/Renderer/ShadingBuffersTests.zig");
    _ = @import("Tests/Renderer/SDFProgramTests.zig");
    _ = @import("Tests/UI/LayoutComponentTests.zig");
    _ = @import("Tests/UI/LayoutSystemTests.zig");
    _ = @import("Tests/Pointer/PointerSystemTests.zig");
    _ = @import("Tests/UI/FocusSystemTests.zig");
    _ = @import("Tests/UI/PopupSystemTests.zig");
    _ = @import("Tests/UI/ScrollSystemTests.zig");
    _ = @import("Tests/UI/UIElementTests.zig");
    _ = @import("Tests/UI/StyleSystemTests.zig");
    _ = @import("Tests/Scripts/EventScriptsTests.zig");
    _ = @import("Tests/Scripts/ScriptValuesTests.zig");
    _ = @import("Tests/Scripts/ScriptAccessTests.zig");
    _ = @import("Tests/Scripts/GameEventsTests.zig");
    _ = @import("Tests/UI/WidgetsTests.zig");
    _ = @import("Tests/UI/NumberFieldSystemTests.zig");
    _ = @import("Tests/UI/TreeMenuTests.zig");
    _ = @import("Tests/UI/ShellWidgetsTests.zig");
    _ = @import("Tests/UI/EditorShellTests.zig");
    _ = @import("Tests/UI/EditorMenuBarTests.zig");
    _ = @import("Tests/UI/InspectorTests.zig");
    _ = @import("Tests/UI/InspectorPiecesTests.zig");
    _ = @import("Tests/UI/ComponentRowsTests.zig");
    _ = @import("Tests/EditorPanels/StatsPanelTests.zig");
    _ = @import("Tests/EditorPanels/AudioBusesPanelTests.zig");
    _ = @import("Tests/EditorPanels/ProjectSettingsPanelTests.zig");
    _ = @import("Tests/EditorPanels/UIElementPanelTests.zig");
    _ = @import("Tests/EditorPanels/PickingDebugPanelTests.zig");
    _ = @import("Tests/EditorPanels/ScriptsPanelTests.zig");
    _ = @import("Tests/EditorPanels/ContentBrowserPanelTests.zig");
    _ = @import("Tests/EditorPanels/ComponentsPanelTests.zig");
    _ = @import("Tests/EditorPanels/HierarchyPanelTests.zig");
    _ = @import("Tests/EditorPanels/ReferenceFieldsTests.zig");
    _ = @import("Tests/EditorPanels/TmplPiecesTests.zig");
    _ = @import("Tests/EditorPanels/PlayPreviewTests.zig");
    _ = @import("Tests/EditorPanels/AssetHandlesPanelTests.zig");
    _ = @import("Tests/Core/WorldCopyTests.zig");
    _ = @import("Tests/Core/WorldSystemsTests.zig");
    _ = @import("Tests/Core/WorldBVHTests.zig");
    _ = @import("Tests/Core/EngineStatsTests.zig");
    _ = @import("Tests/Core/ProjectTests.zig");
    _ = @import("Tests/Programs/GameProgramTests.zig");
    _ = @import("Tests/AudioManager/BusSaveTests.zig");
    _ = @import("Tests/AudioManager/VoiceSourceTests.zig");
}

//Core Stuff -----------------------------------
pub const Application = @import("Core/Application.zig");
pub const EditorProgram = @import("Programs/EditorProgram.zig");
pub const GameProgram = @import("Programs/GameProgram.zig");
pub const EngineContext = @import("Core/EngineContext.zig");
pub const Tracy = @import("Core/Tracy.zig");

//Entity stuff ------------------------------------
pub const Entity = @import("ECSObjects/Entity.zig");
pub const EntityComponents = @import("ECSComponents/EComponents.zig");

//Audio Stuff -----------------------------------------
pub const Voice = @import("ECSObjects/Voice.zig");
pub const Bus = @import("ECSObjects/Bus.zig");

//Scene Stuff -----------------------------------------
pub const SceneLayer = @import("ECSObjects/Scene.zig");
pub const SceneComponents = @import("ECSComponents/SComponents.zig");

//Player and Game Context Stuff ------------------------
pub const Player = @import("ECSObjects/Player.zig");
pub const PlayerComponents = @import("ECSComponents/PComponents.zig");
pub const GameContext = @import("ECSObjects/GameContext.zig");
pub const GCComponents = @import("ECSComponents/GCComponents.zig");

//Script Stuff ----------------------------------------------
pub const ScriptResult = @import("Scripts/ScriptABI.zig").ScriptResult;
//what a script's generated DLL root builds itself from (see build_script.zig)
pub const ScriptABI = @import("Scripts/ScriptABI.zig");
pub const ScriptExport = @import("Scripts/ScriptExport.zig");
//game events: an event file's Phase is a GamePhase (see Scripts/GameEvents.zig)
pub const GamePhase = @import("Scripts/GameEvents.zig").GamePhase;
//what a hook touches in another kind of ECS than its owner's: IM.In(IM.GCECS, IM.GCComponents.AttribComponent)
pub const In = @import("ECS/Systems.zig").In;
//the kinds of ECS, for In
pub const EECS = @import("ECSManagers/EManager.zig").ECSManagerT;
pub const SECS = @import("ECSManagers/SManager.zig").ECSManagerT;
pub const PECS = @import("ECSManagers/PManager.zig").ECSManagerT;
pub const GCECS = @import("ECSManagers/GCManager.zig").ECSManagerT;
pub const UIECS = @import("UI/UIManager.zig").ECSManagerT;
pub const AudioECS = @import("AudioManager/AudioManager.zig").ECSManagerT;

//Event Stuff -----------------------------------------------
pub const KeyboardPressedEvent = @import("Events/WindowEventData.zig").KeyboardPressedEvent;
pub const PointerEvent = @import("Events/PointerEventData.zig").PointerEvent;
pub const PointerEventData = @import("Events/PointerEventData.zig");
pub const UIEvent = @import("Events/UIEventData.zig").UIEvent;
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
pub const CollisionMask = @import("Physics/CollisionMask.zig");

//Rendering Stuff -------------------------------------------
pub const PushConstants = @import("Renderer/RenderPipeline.zig").PushConstants;
pub const ShapeData = @import("Renderer/Renderer2D.zig").ShapeData;
pub const ShapeSurface = @import("Renderer/Renderer2D.zig").ShapeSurface;
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
