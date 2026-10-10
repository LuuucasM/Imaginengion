//! What a world asks the program to do about the whole world, e.g. from a script. Queued on that world's
//! WorldManager (mEventManager) and handled at the end of the frame, since what reacts can clear or replace the
//! world the script was running in. Each event names the world it came from, so the program can tell the game
//! being played apart from the editor's own worlds. SceneLoaded is the exception: dispatched synchronously, never queued
const WorldManager = @import("../Core/WorldManager.zig");
const Scene = @import("../ECSObjects/Scene.zig");

pub const EventCategories = enum {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    QuitGame: QuitGameEvent,
    SceneLoaded: SceneLoadedEvent,
};

pub const DefaultEvent = struct {};

/// The game asks to quit, e.g. from a script on a quit button (WorldManager.QuitGame). In the editor this stops
/// the simulation when mWorld is the one being played
pub const QuitGameEvent = struct {
    mWorld: *WorldManager,
};

/// mScene has just been put in mWorld, from a file or a template (WorldManager.Load, WorldManager.Spawn), with
/// everything in it. Dispatched synchronously (EventManager.Dispatch), never queued, so whoever loaded it gets it back
/// already set up. The program runs the scene's OnSceneStart scripts on it when mWorld is the one being played
pub const SceneLoadedEvent = struct {
    mWorld: *WorldManager,
    mScene: Scene,
};
