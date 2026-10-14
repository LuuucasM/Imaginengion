//! The tags on a script child that say which of its script's hooks run: one for each hook the script has (see
//! ScriptABI.Hook), given by ScriptsProcessor.SetUpScript from the script's DLL. A tag is what the engine queries for,
//! its Hook which of the script's functions it calls
const EngineContext = @import("../../Core/EngineContext.zig");
const ScriptHook = @import("../../Scripts/ScriptABI.zig").Hook;

//ENTITY SCRIPTS
/// Handed every key pressed, like an OnKeyPressed for a player, and checks which it got
pub const OnKeyPressedScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnKeyPressedScript";
    pub const Hook: ScriptHook = .OnKeyPressed;
    pub fn Deinit(_: *OnKeyPressedScript, _: *EngineContext) void {}
};

pub const EntityOnUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnUpdateScript";
    pub const Hook: ScriptHook = .OnUpdate;
    pub fn Deinit(_: *EntityOnUpdateScript, _: *EngineContext) void {}
};

/// Runs once when the owner's collider starts touching another one (see CollisionBeginEvent), whatever
/// it touched: like a key pressed script being handed every key, the script itself checks what it hit.
/// Handed the entity it hit and the contact as the owner sees it
pub const OnCollisionBeginScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnCollisionBeginScript";
    pub const Hook: ScriptHook = .OnCollisionBegin;
    pub fn Deinit(_: *OnCollisionBeginScript, _: *EngineContext) void {}
};

/// Runs once when the owner's collider stops touching another one (see CollisionEndEvent), the counterpart of
/// OnCollisionBeginScript: every collision that began ends once. Handed the same CollisionInfo, with a zero normal.
/// It still runs when the other entity was deleted, which ends the collision too, so check other.IsActive() before
/// reading anything off it. An owner that was deleted is not run at all
pub const OnCollisionEndScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnCollisionEndScript";
    pub const Hook: ScriptHook = .OnCollisionEnd;
    pub fn Deinit(_: *OnCollisionEndScript, _: *EngineContext) void {}
};

/// Runs from the middle of the physics step, before the solver acts on a solid contact of the owner's, every substep
/// the contact is there (see PreSolveEvent). Only for contacts where one of the two colliders has mPreSolveEvents on.
/// Set info.mEnabled to false to have the two pass through each other on this substep, e.g. a one way platform.
/// The step's contact lists are live while it runs: read the world and decide, never create, delete or move anything
pub const OnPreSolveScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnPreSolveScript";
    pub const Hook: ScriptHook = .OnPreSolve;
    pub fn Deinit(_: *OnPreSolveScript, _: *EngineContext) void {}
};

/// Runs at the start of every physics step, at the physics' own fixed rate rather than once a frame (see
/// PhysicsEventData.StepBeginEvent): the place for anything the physics should feel, like forces. A force
/// applied here pushes for the whole step and is let go of after it. Handed the length of the step in seconds
pub const EntityOnPhysicsUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "EntityOnPhysicsUpdateScript";
    pub const Hook: ScriptHook = .OnPhysicsUpdate;
    pub fn Deinit(_: *EntityOnPhysicsUpdateScript, _: *EngineContext) void {}
};

/// Runs for every pointer event sent to the owner (see Events/PointerEventData.zig): entered, exited, pressed,
/// released, clicked, dragged, dropped on. Only the owner's own events reach it, so it never checks who an event is
/// for; like a key pressed script being handed every key, it checks which event it got. The pointer's events go to what it is over and then to each thing that is inside of, so a script on a
/// panel hears clicks on its rows too, and the event's mTarget is what was actually under the pointer. Returning
/// .Handled keeps a press, click, drag or drop from going on to the owner's parents (an enter or exit is each one's own)
pub const OnPointerEventScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnPointerEventScript";
    pub const Hook: ScriptHook = .OnPointerEvent;
    pub fn Deinit(_: *OnPointerEventScript, _: *EngineContext) void {}
};

/// OnPointerEventScript for the UI's events (see Events/UIEventData.zig): a text input getting or losing the keyboard,
/// its text changing or being submitted, a popup opening or closing. Run right after the pointer's events
pub const OnUIEventScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnUIEventScript";
    pub const Hook: ScriptHook = .OnUIEvent;
    pub fn Deinit(_: *OnUIEventScript, _: *EngineContext) void {}
};

/// On a script that has nothing to run: it does not load (it does not compile, say), or it is a script for another
/// kind of object. Given by ScriptsProcessor.SetUpScript, and taken off again once the script's file is changed and it
/// loads as a script for this object. For all four object types. Never saved
pub const UntypedScriptTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "UntypedScriptTag";
    pub fn Deinit(_: *UntypedScriptTag, _: *EngineContext) void {}
};

/// On a script child whose script handles game events (any of its functions takes one, see Scripts/GameEvents.zig), so
/// ScriptsProcessor.ProcessGameEvents only looks at those. For all four object types, given by SetUpScript. Never saved
pub const GameEventScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "GameEventScript";
    pub fn Deinit(_: *GameEventScript, _: *EngineContext) void {}
};

//SCENE SCRIPTS
/// Runs once when the scene is loaded while the game runs, and for every scene when the game starts
pub const OnSceneStartScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnSceneStartScript";
    pub const Hook: ScriptHook = .OnSceneStart;
    pub fn Deinit(_: *OnSceneStartScript, _: *EngineContext) void {}
};

/// Runs once a frame for each scene, after the players' OnUpdate scripts and before the entities'
pub const SceneOnUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "SceneOnUpdateScript";
    pub const Hook: ScriptHook = .OnUpdate;
    pub fn Deinit(_: *SceneOnUpdateScript, _: *EngineContext) void {}
};

/// EntityOnPhysicsUpdateScript for a scene, e.g. a rule that pushes on every body in it. A scene's run before its
/// entities' on each step
pub const SceneOnPhysicsUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "SceneOnPhysicsUpdateScript";
    pub const Hook: ScriptHook = .OnPhysicsUpdate;
    pub fn Deinit(_: *SceneOnPhysicsUpdateScript, _: *EngineContext) void {}
};

//PLAYER SCRIPTS
/// Runs once a frame for each player, after the game context's OnUpdate scripts and before the scenes'
pub const PlayerOnUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "PlayerOnUpdateScript";
    pub const Hook: ScriptHook = .OnUpdate;
    pub fn Deinit(_: *PlayerOnUpdateScript, _: *EngineContext) void {}
};

/// OnKeyPressedScript for a player: handed every key, like the entities' ones, and checks which it got. Hears what the
/// scene stack leaves, so after every entity's key pressed scripts, and only if none of them handled it. A key the UI
/// takes (a text input with the keyboard) never reaches it
pub const PlayerOnInputPressedScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "PlayerOnInputPressedScript";
    pub const Hook: ScriptHook = .OnKeyPressed;
    pub fn Deinit(_: *PlayerOnInputPressedScript, _: *EngineContext) void {}
};

//GAME CONTEXT SCRIPTS
/// Runs once when the game starts (Play in the editor, launching a built game), before the scenes' OnSceneStart
/// scripts: the place to set up the game's rules
pub const OnGameStartScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "OnGameStartScript";
    pub const Hook: ScriptHook = .OnGameStart;
    pub fn Deinit(_: *OnGameStartScript, _: *EngineContext) void {}
};

/// Runs once a frame for the game context, first of all the OnUpdate scripts
pub const GameContextOnUpdateScript = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "GameContextOnUpdateScript";
    pub const Hook: ScriptHook = .OnUpdate;
    pub fn Deinit(_: *GameContextOnUpdateScript, _: *EngineContext) void {}
};
