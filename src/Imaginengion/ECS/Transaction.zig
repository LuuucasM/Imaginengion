//! What one transaction has changed so far, kept apart from storage until it ends: Commit puts it in, Discard drops it,
//! as if it never happened. The systems layer opens one around a piece of code (Systems.RunTransaction), and while it is
//! open every ECS the layer knows reads and writes components through it:
//!
//!   - GetComponentMut copies the component in here the first time (a deep copy for a type with a Clone) and hands
//!     back the copy, the same copy every time after
//!   - GetComponent hands back the copy if there is one, so the code sees what it has changed itself
//!
//! Only component values so far: adds, removes, destroys, tags and parent/child links aren't held here yet, and nor is
//! anything outside the ECSs. Neither is a component staged during the run, which is handed out as it is.
const Transaction = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");

/// The copies, in the order they were first made
mEntries: std.ArrayList(Entry) = .empty,
/// Where each copy is in mEntries, by what it is a copy of
mLookup: std.AutoHashMapUnmanaged(Key, usize) = .empty,
/// Where the copies themselves live, so a pointer handed out stays good until the transaction ends
mArena: std.heap.ArenaAllocator.State = .init,
/// The context the transaction was opened with (Open): GetComponentMut has none of its own to copy with
mEngineContext: ?*EngineContext = null,

pub const empty: Transaction = .{};

/// What a copy is a copy of: one component array (a type in one ECS), and the entity in it
pub const Key = struct {
    mArray: *anyopaque,
    mEntityID: u64,
};

/// Puts a copy in place of the component in `array`, or deinitializes the copy if the component is gone by then.
/// Filled in for the copy's type by the array it came from (InternalComponentArray.CommitCopy)
pub const CommitFn = *const fn (array: *anyopaque, engine_context: *EngineContext, entity_id: u64, copy: *anyopaque) void;

const Entry = struct {
    mKey: Key,
    mCopy: *anyopaque,
    mCommit: CommitFn,
    mDiscard: *const fn (engine_context: *EngineContext, copy: *anyopaque) void,
};

pub fn Deinit(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mEntries.items.len == 0);
    self.mEntries.deinit(engine_allocator);
    self.mLookup.deinit(engine_allocator);
    self.mArena.promote(engine_allocator).deinit();
    self.* = .empty;
}

/// The copy of this component made in this transaction, null if there isn't one yet
pub fn Find(self: *const Transaction, key: Key) ?*anyopaque {
    // most of the time nothing has been copied, which keeps GetComponent from costing a lookup
    if (self.mEntries.items.len == 0) return null;
    const entry_ind = self.mLookup.get(key) orelse return null;
    return self.mEntries.items[entry_ind].mCopy;
}

/// Starts the transaction, which has to be empty
pub fn Open(self: *Transaction, engine_context: *EngineContext) void {
    std.debug.assert(self.mEntries.items.len == 0);
    self.mEngineContext = engine_context;
}

/// Copies `source`, the component `key` names, into the transaction and hands back the copy. There mustn't be one already
pub fn Copy(self: *Transaction, key: Key, comptime T: type, source: *const T, commit: CommitFn) !*T {
    std.debug.assert(!self.mLookup.contains(key));
    const engine_context = self.mEngineContext.?;
    const engine_allocator = engine_context.EngineAllocator();
    try self.mEntries.ensureUnusedCapacity(engine_allocator, 1);
    try self.mLookup.ensureUnusedCapacity(engine_allocator, 1);

    var arena = self.mArena.promote(engine_allocator);
    defer self.mArena = arena.state;
    const copy = try arena.allocator().create(T);
    // a component that owns memory copies itself, so the copy can change it without touching the original's
    copy.* = if (@hasDecl(T, "Clone")) try source.Clone(engine_context) else source.*;

    self.mLookup.putAssumeCapacity(key, self.mEntries.items.len);
    self.mEntries.appendAssumeCapacity(.{
        .mKey = key,
        .mCopy = copy,
        .mCommit = commit,
        .mDiscard = struct {
            fn Discard(context: *EngineContext, erased: *anyopaque) void {
                const typed: *T = @ptrCast(@alignCast(erased));
                typed.Deinit(context);
            }
        }.Discard,
    });
    return copy;
}

/// Puts every copy in place of its component, in the order they were made, and empties the transaction
pub fn Commit(self: *Transaction, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Transaction::Commit", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len);
    for (self.mEntries.items) |entry| entry.mCommit(entry.mKey.mArray, engine_context, entry.mKey.mEntityID, entry.mCopy);
    self._Reset(engine_context.EngineAllocator());
}

/// Deinitializes every copy, leaving the components as they were before the transaction, and empties it
pub fn Discard(self: *Transaction, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Transaction::Discard", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len);
    for (self.mEntries.items) |entry| entry.mDiscard(engine_context, entry.mCopy);
    self._Reset(engine_context.EngineAllocator());
}

fn _Reset(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    self.mEngineContext = null;
    self.mEntries.clearRetainingCapacity();
    self.mLookup.clearRetainingCapacity();
    var arena = self.mArena.promote(engine_allocator);
    _ = arena.reset(.retain_capacity);
    self.mArena = arena.state;
}
