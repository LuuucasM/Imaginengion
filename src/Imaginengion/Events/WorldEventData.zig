//! What a world asks the program to do about the whole world, e.g. from a script. Queued on that world's
//! WorldManager (mEventManager) and handled at the end of the frame, since what reacts can clear or replace the
//! world the script was running in. Each event names the world it came from, so the program can tell the game
//! being played apart from the editor's own worlds
const WorldManager = @import("../Core/WorldManager.zig");

pub const EventCategories = enum {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    QuitGame: QuitGameEvent,
};

pub const DefaultEvent = struct {};

/// The game asks to quit, e.g. from a script on a quit button (WorldManager.QuitGame). In the editor this stops
/// the simulation when mWorld is the one being played
pub const QuitGameEvent = struct {
    mWorld: *WorldManager,
};
