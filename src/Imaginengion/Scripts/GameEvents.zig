//! Game events: events a game's scripts make up themselves. An event is a .zig file in the project, a struct and the
//! phase it is handled in:
//!     pub const Phase: IM.GamePhase = .AfterUpdate;
//!     mScorer: enum { Player, AI } = .Player,
//! A script imports it by its file name, @import("ScoreEvent"), sends it with world.Emit (WorldManager.Emit), and
//! handles it with a function of any name whose last parameter is it (see ScriptExport). The engine never knows the
//! event's type: each world keeps the events sent in it as bytes tagged with the event's id (GameEventManager), and at
//! the event's phase hands them to the scripts with a handler for that id (ScriptsProcessor.ProcessGameEvents).
//! The id comes from the event's name, the same in every script's DLL. That is safe through renames and edits because
//! a script is rebuilt whenever a file it imports changes, and stops if that rebuild fails (ScriptsProcessor.SyncScripts)
const std = @import("std");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");

/// When a world's game events are handled in the frame
pub const GamePhase = enum {
    /// right after the physics step's own events, before any OnUpdate
    AfterPhysics,
    /// after every OnUpdate, before layout and drawing, so what reacts shows the same frame
    AfterUpdate,
};

/// The most an event's alignment can be: it is handed to its handlers from a copy aligned to this
pub const MAX_ALIGN = 16;

/// Whether T is a game event: a struct with a Phase
pub fn IsEvent(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "Phase");
}

/// An event's name, its file's name for an event imported by name: the last part of its type's name
pub fn NameOf(comptime T: type) [:0]const u8 {
    const full = @typeName(T);
    return full[if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot| dot + 1 else 0..];
}

/// An event's id, what its queued bytes and its handlers are matched by: the same in every DLL built with it
pub fn IdOf(comptime T: type) u64 {
    return comptime std.hash.Fnv1a_64.hash(NameOf(T));
}

pub fn PhaseOf(comptime T: type) GamePhase {
    return T.Phase;
}

/// Compile errors for a type that can't be a game event: no Phase, or something in it that can't sit in a queue as
/// bytes (a slice, a pointer, anything owning memory). Object handles are fine, they are ids into the same world
pub fn Check(comptime T: type) void {
    const name = NameOf(T);
    if (!IsEvent(T)) @compileError(@typeName(T) ++ " is not a game event: an event is a struct file with pub const Phase: IM.GamePhase = .AfterUpdate (or .AfterPhysics)");
    _ = PhaseOf(T); //a Phase that isn't a GamePhase is an error here
    if (@alignOf(T) > MAX_ALIGN) @compileError(name ++ " needs more alignment than an event can have");
    CheckPlainData(T, name, name);
}

fn CheckPlainData(comptime T: type, comptime event_name: []const u8, comptime where: []const u8) void {
    if (T == Entity or T == Scene or T == Player or T == GameContext) return;
    switch (@typeInfo(T)) {
        .int, .float, .bool, .@"enum", .vector, .void => {},
        .array => |array| CheckPlainData(array.child, event_name, where ++ "[]"),
        .optional => |optional| CheckPlainData(optional.child, event_name, where),
        .@"struct" => |info| {
            inline for (info.field_names, info.field_types) |field_name, field_type| {
                CheckPlainData(field_type, event_name, where ++ "." ++ field_name);
            }
        },
        .@"union" => |info| {
            inline for (info.field_names, info.field_types) |field_name, field_type| {
                CheckPlainData(field_type, event_name, where ++ "." ++ field_name);
            }
        },
        else => @compileError(event_name ++ ": " ++ where ++ " is a " ++ @typeName(T) ++ ", which an event can't hold. " ++
            "An event is kept as bytes until it is handled, so it holds plain data: numbers, bools, enums, vectors, " ++
            "Entity, SceneLayer, Player or GameContext, and structs and arrays of those"),
    }
}

/// One world's game events waiting for their phase, as bytes: nothing here knows any event's type
pub const GameEventManager = struct {
    pub const Entry = struct {
        mId: u64,
        mOffset: u32,
        mSize: u32,
    };

    pub const Queue = struct {
        /// every queued event's bytes, one after another
        mBytes: std.ArrayList(u8) = .empty,
        mEntries: std.ArrayList(Entry) = .empty,

        /// Entry `index`'s bytes. Only until the next Insert, which can move them
        pub fn BytesOf(self: *const Queue, index: usize) []const u8 {
            const entry = self.mEntries.items[index];
            return self.mBytes.items[entry.mOffset..][0..entry.mSize];
        }
    };

    pub const empty: GameEventManager = .{};

    mQueues: std.EnumArray(GamePhase, Queue) = .initFill(.{}),

    pub fn Deinit(self: *GameEventManager, engine_allocator: std.mem.Allocator) void {
        for (&self.mQueues.values) |*queue| {
            queue.mBytes.deinit(engine_allocator);
            queue.mEntries.deinit(engine_allocator);
        }
    }

    /// Queues an event of id `id` for `phase`
    pub fn Insert(self: *GameEventManager, engine_allocator: std.mem.Allocator, phase: GamePhase, id: u64, bytes: []const u8) !void {
        const queue = self.mQueues.getPtr(phase);
        const offset = queue.mBytes.items.len;
        try queue.mBytes.appendSlice(engine_allocator, bytes);
        errdefer queue.mBytes.shrinkRetainingCapacity(offset);
        try queue.mEntries.append(engine_allocator, .{ .mId = id, .mOffset = @intCast(offset), .mSize = @intCast(bytes.len) });
    }

    pub fn GetQueue(self: *GameEventManager, phase: GamePhase) *Queue {
        return self.mQueues.getPtr(phase);
    }

    /// Empties `phase`'s queue, once its events are handled
    pub fn Clear(self: *GameEventManager, phase: GamePhase) void {
        const queue = self.mQueues.getPtr(phase);
        queue.mBytes.clearRetainingCapacity();
        queue.mEntries.clearRetainingCapacity();
    }

    /// Empties every queue and frees them, with the world they are about
    pub fn ClearAndFree(self: *GameEventManager, engine_allocator: std.mem.Allocator) void {
        self.Deinit(engine_allocator);
        self.* = .empty;
    }
};
