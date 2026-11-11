//! What one transaction has changed so far, kept apart until it ends: Commit keeps it, Discard drops it, as if it never
//! happened. The transactions layer opens one around a piece of code (Transactions.RunTransaction, or one per hook in
//! Transactions.RunBatch), which also counts as a run, and while it is open every ECS the layer knows goes through it:
//!
//!   - Component values: GetComponentMut copies the component in here the first time (a deep copy for a type with a
//!     Clone) and hands back the copy, the same copy every time after. GetComponent hands back the copy if there is one,
//!     so the code sees what it has changed itself. Commit puts the copies in place, Discard drops them.
//!   - Structure: adds, tags put on or taken off, removals and destroys are held here as ops, in the order asked for.
//!     The code sees its own (HasComponent, GetComponent, GetGroup and NumWithComponent look here too); nothing else does.
//!     Commit hands each to its ECS to make the way it would have been made straight away (an add staged, a tag put on,
//!     a removal queued); Discard drops them, undoing what an add set off through the removal hook.
//!   - Objects made (CreateEntity, CreateScript, AddChild): made at once, written down, and destroyed by Discard. Not
//!     while speculating, see below.
//!   - Anything else: code outside the ECSs says what to do at commit (OnCommit, e.g. send an event it held back) or at
//!     discard (OnDiscard, e.g. put a script's variables back).
//!   - What can't be taken back at all (a file written, a popup's state): the code doing it marks the transaction
//!     (MarkIrrevocable), and a marked transaction is kept even when its code fails, rather than coming out half undone.
//!
//! A speculating transaction (one hook of a batch, Transactions.RunBatch) may be dropped and run again, so it mustn't do
//! anything for real: making an object or anything irrevocable is refused with error.RunSerially (or error.Canceled from
//! the engine's Io) and marks it (mRunSerially), and the batch runs it again on its own afterwards.
//!
//! Not held here: a staged component taken back off with RemoveComponentSync (gone for good), and a component staged
//! before the transaction, which is handed out as it is rather than copied.
const Transaction = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");

/// The copies, in the order they were first made
mEntries: std.ArrayList(Entry) = .empty,
/// Where each copy is in mEntries, by what it is a copy of
mLookup: std.AutoHashMapUnmanaged(Key, usize) = .empty,
/// Where the copies, held adds and actions' data live, so a pointer handed out stays good until the transaction ends
mArena: std.heap.ArenaAllocator.State = .init,
/// The context the transaction was opened with (Open): GetComponentMut has none of its own to copy with
mEngineContext: ?*EngineContext = null,
/// The structural changes held, oldest first
mOps: std.ArrayList(Op) = .empty,
/// For each component an op put on or took off an entity (an add or a tag), the newest such op: what reads see
mPresence: std.AutoHashMapUnmanaged(Key, usize) = .empty,
/// The objects made in this transaction, oldest first
mCreated: std.ArrayList(Undo) = .empty,
/// What to do if the transaction is kept, in order
mOnCommit: std.ArrayList(Action) = .empty,
/// What to do if the transaction is dropped, newest first
mOnDiscard: std.ArrayList(Action) = .empty,
/// Why the transaction can't be dropped, null while it still can (MarkIrrevocable)
mIrrevocable: ?[]const u8 = null,

/// One hook of a batch, which may be dropped and run again: nothing it does may happen for real before commit. Set by Open
mSpeculating: bool = false,
/// Its code said what it was for didn't happen (Transactions.MarkFailed): it is dropped rather than kept
mFailed: bool = false,
/// While speculating, the hook asked for something that can't be speculative (an object made, an irrevocable action):
/// it is dropped whatever it hands back, and run again on its own after the batch
mRunSerially: bool = false,

/// Whether this transaction writes down what it reads and writes: for a batch's conflict check, and for the conflict
/// report (Transactions.mConflicts). Set by Open
mMeasuring: bool = false,
/// While measuring: each component it read or wrote, by entity (a value, or whether it is there at all)
mReads: std.AutoHashMapUnmanaged(Key, void) = .empty,
mWrites: std.AutoHashMapUnmanaged(Key, void) = .empty,
/// While measuring: each type it read or wrote as a whole (which entities have it, or every value)
mTypeReads: std.AutoHashMapUnmanaged(TypeKey, void) = .empty,
mTypeWrites: std.AutoHashMapUnmanaged(TypeKey, void) = .empty,
/// While measuring: each array's component type name, for the report. Good until the transaction ends
mNames: std.AutoHashMapUnmanaged(*anyopaque, []const u8) = .empty,
/// The array mNames was last given a name for: notes come in runs on one array (a GetComponentMut notes it up to five
/// times), so this skips the put for all but the first
mLastNamed: ?*anyopaque = null,
/// While measuring, something couldn't be written down (out of memory): it can't be checked for conflicts
mMeasureLost: bool = false,


pub const empty: Transaction = .{};

/// How a transaction is opened
pub const Options = struct {
    /// write down what it reads and writes
    mMeasuring: bool = false,
    /// one hook of a batch: refuse what can't be speculative
    mSpeculating: bool = false,
};

/// A whole component array (a type in one ECS) read or written as one
pub const TypeKey = struct {
    mArray: *anyopaque,
    mAccess: TypeAccess,
};

pub const TypeAccess = enum {
    /// which entities have the type: GetGroup and NumWithComponent read it, adds and tags change it
    Membership,
    /// every value of the type: GetComponentSlice reads it, any change to a value changes it
    Values,
};

/// Something to do when the transaction ends, with its data in the transaction's arena (OnCommit, OnDiscard)
pub const Action = struct {
    mData: *anyopaque,
    mRun: *const fn (engine_context: *EngineContext, data: *anyopaque) void,
};

/// One component of one entity: one component array (a type in one ECS), and the entity in it
pub const Key = struct {
    mArray: *anyopaque,
    mEntityID: u64,
};

/// How a component of one type is copied in, put back and dropped: the component array's own functions
/// (ComponentArray.CopyFns), filled in by the engine when the ECS was made. Never the component type's functions
/// themselves, which a script DLL's copy of this code would have to compile, C calls in their Deinit and all
pub const CopyFns = struct {
    /// A copy of the component in the arena given, deep for a type with a Clone
    mClone: *const fn (engine_context: *EngineContext, arena: std.mem.Allocator, source: *const anyopaque) anyerror!*anyopaque,
    /// Puts a copy in place of the component in `array`, or deinitializes the copy if the component is gone by then
    mCommit: *const fn (array: *anyopaque, engine_context: *EngineContext, entity_id: u64, copy: *anyopaque) void,
    /// Deinitializes a copy that won't be put back
    mDiscard: *const fn (engine_context: *EngineContext, copy: *anyopaque) void,
};

const Entry = struct {
    mKey: Key,
    mCopy: *anyopaque,
    mFns: CopyFns,
};

pub const OpKind = enum {
    /// a data component added: staged in the ECS at commit
    Add,
    /// a tag put on (mOn) or taken off
    Tag,
    /// a component taken off: queued at commit, readable until the run ends like any removal
    Remove,
    /// an object destroyed: queued at commit
    Destroy,
};

/// One structural change held until the transaction ends. Its ECS fills in what makes it (mApply, at commit) and what
/// drops it (mDrop, at discard)
pub const Op = struct {
    mECS: *anyopaque,
    mKind: OpKind,
    mEntityID: u64,
    mComponentInd: usize = 0,
    /// Add and Tag: the component's array, which reads look it up by
    mArray: ?*anyopaque = null,
    /// Tag: put on, or taken off
    mOn: bool = true,
    /// Add: the value
    mData: ?*anyopaque = null,
    /// Add: the value is in this transaction's arena, rather than already in the ECS's staging arena
    mDataInArena: bool = false,
    /// Made or dropped already, and skipped from then on
    mDone: bool = false,
    mApply: *const fn (ecs: *anyopaque, engine_context: *EngineContext, op: *Op) void,
    mDrop: *const fn (ecs: *anyopaque, engine_context: *EngineContext, op: *Op) void,
};

/// One object made, and what destroys it
pub const Undo = struct {
    mECS: *anyopaque,
    mEntityID: u64,
    mUndo: *const fn (ecs: *anyopaque, engine_context: *EngineContext, entity_id: u64) void,
};

/// What kept transactions have written, for checking a later one against (ConflictOn): a batch's commits so far, or
/// the conflict report's
pub const WriteSet = struct {
    mWrites: std.AutoHashMapUnmanaged(Key, void) = .empty,
    mTypeWrites: std.AutoHashMapUnmanaged(TypeKey, void) = .empty,

    pub fn Deinit(self: *WriteSet, engine_allocator: std.mem.Allocator) void {
        self.mWrites.deinit(engine_allocator);
        self.mTypeWrites.deinit(engine_allocator);
    }

    pub fn Clear(self: *WriteSet) void {
        self.mWrites.clearRetainingCapacity();
        self.mTypeWrites.clearRetainingCapacity();
    }

    /// Adds what `transaction` wrote
    pub fn Add(self: *WriteSet, engine_allocator: std.mem.Allocator, transaction: *const Transaction) !void {
        var writes = transaction.mWrites.keyIterator();
        while (writes.next()) |key| try self.mWrites.put(engine_allocator, key.*, {});
        var type_writes = transaction.mTypeWrites.keyIterator();
        while (type_writes.next()) |key| try self.mTypeWrites.put(engine_allocator, key.*, {});
    }
};

/// Aria's reservation table for one round of a batch (Transactions.RunBatch): for each key written, the lowest place in
/// the batch (Aria's TID) of a hook that writes it. Whole types are reserved apart from single components: a type is
/// written as a whole by any add or tag of it, and only a read of the whole type (a query) can conflict with that
pub const Reservations = struct {
    mKeys: std.AutoHashMapUnmanaged(Key, usize) = .empty,
    mTypes: std.AutoHashMapUnmanaged(TypeKey, usize) = .empty,

    pub fn Deinit(self: *Reservations, engine_allocator: std.mem.Allocator) void {
        self.mKeys.deinit(engine_allocator);
        self.mTypes.deinit(engine_allocator);
    }

    pub fn Clear(self: *Reservations) void {
        self.mKeys.clearRetainingCapacity();
        self.mTypes.clearRetainingCapacity();
    }

    /// ReserveWrite: every key `transaction`, at place `index` in the batch, writes is reserved by the lowest place
    /// writing it
    pub fn Reserve(self: *Reservations, engine_allocator: std.mem.Allocator, transaction: *const Transaction, index: usize) !void {
        var writes = transaction.mWrites.keyIterator();
        while (writes.next()) |key| try _ReserveMin(&self.mKeys, engine_allocator, key.*, index);
        var type_writes = transaction.mTypeWrites.keyIterator();
        while (type_writes.next()) |key| try _ReserveMin(&self.mTypes, engine_allocator, key.*, index);
    }

    fn _ReserveMin(map: anytype, engine_allocator: std.mem.Allocator, key: anytype, index: usize) !void {
        const entry = try map.getOrPut(engine_allocator, key);
        if (!entry.found_existing or index < entry.value_ptr.*) entry.value_ptr.* = index;
    }

    fn _ReservedBefore(map: anytype, key: anytype, index: usize) bool {
        const reserved_by = map.get(key) orelse return false;
        return reserved_by < index;
    }
};

pub fn Deinit(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self._IsEmpty());
    self.mEntries.deinit(engine_allocator);
    self.mLookup.deinit(engine_allocator);
    self.mArena.promote(engine_allocator).deinit();
    self.mOps.deinit(engine_allocator);
    self.mPresence.deinit(engine_allocator);
    self.mCreated.deinit(engine_allocator);
    self.mOnCommit.deinit(engine_allocator);
    self.mOnDiscard.deinit(engine_allocator);
    self.mReads.deinit(engine_allocator);
    self.mWrites.deinit(engine_allocator);
    self.mTypeReads.deinit(engine_allocator);
    self.mTypeWrites.deinit(engine_allocator);
    self.mNames.deinit(engine_allocator);
    self.* = .empty;
}

/// Starts the transaction, which has to be empty
pub fn Open(self: *Transaction, engine_context: *EngineContext, options: Options) void {
    std.debug.assert(self._IsEmpty());
    self.mEngineContext = engine_context;
    self.mMeasuring = options.mMeasuring;
    self.mSpeculating = options.mSpeculating;
}

/// The copy of this component made in this transaction, null if there isn't one yet
pub fn Find(self: *const Transaction, key: Key) ?*anyopaque {
    // most of the time nothing has been copied, which keeps GetComponent from costing a lookup
    if (self.mEntries.items.len == 0) return null;
    const entry_ind = self.mLookup.get(key) orelse return null;
    return self.mEntries.items[entry_ind].mCopy;
}

/// Copies `source`, the component `key` names, into the transaction and hands back the copy. There mustn't be one already
pub fn Copy(self: *Transaction, key: Key, source: *const anyopaque, fns: CopyFns) !*anyopaque {
    std.debug.assert(!self.mLookup.contains(key));
    const engine_context = self.mEngineContext.?;
    const engine_allocator = engine_context.EngineAllocator();
    try self.mEntries.ensureUnusedCapacity(engine_allocator, 1);
    try self.mLookup.ensureUnusedCapacity(engine_allocator, 1);

    var arena = self.mArena.promote(engine_allocator);
    defer self.mArena = arena.state;
    // a component that owns memory copies itself, so the copy can change it without touching the original's
    const copy = try fns.mClone(engine_context, arena.allocator(), source);

    self.mLookup.putAssumeCapacity(key, self.mEntries.items.len);
    self.mEntries.appendAssumeCapacity(.{ .mKey = key, .mCopy = copy, .mFns = fns });
    return copy;
}

//----------------structure held until commit (the ECSs call these)----------------

/// Room for a value of `T` in the transaction's arena, good until it ends: for an add's value (Op.mData)
pub fn Create(self: *Transaction, comptime T: type) !*T {
    var arena = self.mArena.promote(self.mEngineContext.?.EngineAllocator());
    defer self.mArena = arena.state;
    return try arena.allocator().create(T);
}

/// Holds a structural change until the transaction ends. An add or a tag becomes what reads of that component see
pub fn AddOp(self: *Transaction, op: Op) !void {
    const engine_allocator = self.mEngineContext.?.EngineAllocator();
    try self.mOps.ensureUnusedCapacity(engine_allocator, 1);
    if (op.mKind == .Add or op.mKind == .Tag) {
        try self.mPresence.put(engine_allocator, .{ .mArray = op.mArray.?, .mEntityID = op.mEntityID }, self.mOps.items.len);
    }
    self.mOps.appendAssumeCapacity(op);
}

/// The newest add or tag op held for this component, null if there is none: then reads go to the ECS as usual
pub fn Presence(self: *Transaction, key: Key) ?*Op {
    // most of the time nothing is held, which keeps HasComponent from costing a lookup
    if (self.mPresence.count() == 0) return null;
    const op_ind = self.mPresence.get(key) orelse return null;
    const op = &self.mOps.items[op_ind];
    return if (op.mDone) null else op;
}

/// Makes room to write down an object about to be made (AddCreated), so that once it is made writing it down can't fail
pub fn ReserveCreated(self: *Transaction) !void {
    try self.mCreated.ensureUnusedCapacity(self.mEngineContext.?.EngineAllocator(), 1);
}

/// Writes down an object just made, after ReserveCreated
pub fn AddCreated(self: *Transaction, created: Undo) void {
    self.mCreated.appendAssumeCapacity(created);
}

/// Refuses something that can't be done while speculating: marks the transaction to be run again on its own, and hands
/// back the error to refuse with. Null when it isn't speculating, and the thing can go ahead
pub fn RefuseSpeculative(self: *Transaction) ?error{RunSerially} {
    if (!self.mSpeculating) return null;
    self.mRunSerially = true;
    return error.RunSerially;
}

//----------------actions, and what can't be taken back----------------

/// Runs `run(engine_context, &data)` if the transaction is kept, after the copies are in, in the order these were asked
/// for: for something code outside the ECSs holds back until then (an event it sends). `data` is copied into the
/// transaction's arena; a slice in it has to be too (Dupe)
pub fn OnCommit(self: *Transaction, data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    try self._AddAction(&self.mOnCommit, data, run);
}

/// Runs `run(engine_context, &data)` if the transaction is dropped, before anything else is undone, newest first: for
/// putting back something code outside the ECSs changed (a script's variables). `data` is copied as for OnCommit
pub fn OnDiscard(self: *Transaction, data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    try self._AddAction(&self.mOnDiscard, data, run);
}

/// A copy of `bytes` in the transaction's arena, good until the transaction ends: for an action's data with a slice in it
pub fn Dupe(self: *Transaction, bytes: []const u8) ![]u8 {
    var arena = self.mArena.promote(self.mEngineContext.?.EngineAllocator());
    defer self.mArena = arena.state;
    return try arena.allocator().dupe(u8, bytes);
}

/// Says the transaction has done something that can't be taken back, so it is kept even if its code fails: it never
/// comes out half undone. `reason` is for the log line saying so, and has to outlive the transaction (a string literal).
/// The first reason given is the one kept. Refused while speculating (error.RunSerially), when the caller mustn't go on
pub fn MarkIrrevocable(self: *Transaction, reason: []const u8) error{RunSerially}!void {
    if (self.RefuseSpeculative()) |err| return err;
    if (self.mIrrevocable == null) self.mIrrevocable = reason;
}

fn _AddAction(self: *Transaction, list: *std.ArrayList(Action), data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    const T = @TypeOf(data);
    const engine_allocator = self.mEngineContext.?.EngineAllocator();
    try list.ensureUnusedCapacity(engine_allocator, 1);

    var arena = self.mArena.promote(engine_allocator);
    defer self.mArena = arena.state;
    const stored = try arena.allocator().create(T);
    stored.* = data;

    list.appendAssumeCapacity(.{ .mData = stored, .mRun = struct {
        fn Run(engine_context: *EngineContext, erased: *anyopaque) void {
            run(engine_context, @ptrCast(@alignCast(erased)));
        }
    }.Run });
}

//----------------what it reads and writes, while measuring (the ECSs call these)----------------

/// A component of one entity read, its value or whether it is there. `name` is its type's, for the report
pub fn NoteRead(self: *Transaction, key: Key, name: []const u8) void {
    self._Note(&self.mReads, key, key.mArray, name);
}

/// A component's value changed (or handed out to change)
pub fn NoteValueWrite(self: *Transaction, key: Key, name: []const u8) void {
    self._Note(&self.mWrites, key, key.mArray, name);
    self._Note(&self.mTypeWrites, TypeKey{ .mArray = key.mArray, .mAccess = .Values }, key.mArray, name);
}

/// A component put on or taken off an entity in a way the rest of the run sees once it is kept (an add, a tag)
pub fn NotePresenceWrite(self: *Transaction, key: Key, name: []const u8) void {
    self._Note(&self.mWrites, key, key.mArray, name);
    self._Note(&self.mTypeWrites, TypeKey{ .mArray = key.mArray, .mAccess = .Membership }, key.mArray, name);
}

/// A whole type read as one
pub fn NoteTypeRead(self: *Transaction, array: *anyopaque, access: TypeAccess, name: []const u8) void {
    self._Note(&self.mTypeReads, TypeKey{ .mArray = array, .mAccess = access }, array, name);
}

fn _Note(self: *Transaction, set: anytype, key: anytype, array: *anyopaque, name: []const u8) void {
    const engine_allocator = self.mEngineContext.?.EngineAllocator();
    set.put(engine_allocator, key, {}) catch {
        self.mMeasureLost = true;
        return;
    };
    // an array's name never changes, so once it is in there is nothing to put
    if (self.mLastNamed == array) return;
    self.mNames.put(engine_allocator, array, name) catch {
        self.mMeasureLost = true;
        return;
    };
    self.mLastNamed = array;
}

/// The type name written down for `array`, for the report
pub fn NameOf(self: *const Transaction, array: *anyopaque) []const u8 {
    return self.mNames.get(array) orelse "?";
}

/// Aria's HasConflicts for this transaction at place `index` in its batch: the array of the first thing it read or
/// wrote (RS U WS) that a hook before it reserved, null if none. Whole types: only its reads of a whole type count
pub fn ConflictWith(self: *const Transaction, reservations: *const Reservations, index: usize) ?*anyopaque {
    inline for (.{ &self.mReads, &self.mWrites }) |set| {
        var keys = set.keyIterator();
        while (keys.next()) |key| {
            if (Reservations._ReservedBefore(&reservations.mKeys, key.*, index)) return key.mArray;
        }
    }
    var type_reads = self.mTypeReads.keyIterator();
    while (type_reads.next()) |key| {
        if (Reservations._ReservedBefore(&reservations.mTypes, key.*, index)) return key.mArray;
    }
    return null;
}

/// The array of the first thing this transaction read or wrote that `writes` has, null if none: the conflict report's
/// check of a transaction against those kept before it in a run that isn't a real batch. Whole types: only its reads of
/// a whole type count, as in ConflictWith
pub fn ConflictOn(self: *const Transaction, writes: *const WriteSet) ?*anyopaque {
    inline for (.{ &self.mReads, &self.mWrites }) |set| {
        var keys = set.keyIterator();
        while (keys.next()) |key| {
            if (writes.mWrites.contains(key.*)) return key.mArray;
        }
    }
    var type_reads = self.mTypeReads.keyIterator();
    while (type_reads.next()) |key| {
        if (writes.mTypeWrites.contains(key.*)) return key.mArray;
    }
    return null;
}

//----------------ending it----------------

/// Keeps everything: puts every copy in place of its component, in the order they were made, has each ECS make the
/// structural changes held, in order, runs what was to happen on commit, and empties the transaction
pub fn Commit(self: *Transaction, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Transaction::Commit", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len + self.mOps.items.len);
    for (self.mEntries.items) |entry| entry.mFns.mCommit(entry.mKey.mArray, engine_context, entry.mKey.mEntityID, entry.mCopy);
    for (self.mOps.items) |*op| self._Apply(engine_context, op);
    for (self.mOnCommit.items) |action| action.mRun(engine_context, action.mData);
    self._Reset(engine_context.EngineAllocator());
}

/// Drops everything, leaving the ECSs as they were before the transaction, and empties it. The order matters:
///   1. what was to happen on discard runs, newest first
///   2. what was held for objects it made is made after all, in order, so that the next step can read it
///   3. objects made are destroyed, newest first, the removal hook reading what was held for them (a UUID to forget)
///   4. the rest of what was held is dropped, newest first, an add on a live object going through the removal hook
///   5. the copies are deinitialized
/// What was to happen on commit never does. Not for a transaction marked irrevocable, which can only be kept
pub fn Discard(self: *Transaction, engine_context: *EngineContext) void {
    std.debug.assert(self.mIrrevocable == null);
    const zone = Tracy.ZoneInit("Transaction::Discard", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len + self.mOps.items.len);

    var action_ind = self.mOnDiscard.items.len;
    while (action_ind > 0) {
        action_ind -= 1;
        const action = self.mOnDiscard.items[action_ind];
        action.mRun(engine_context, action.mData);
    }

    if (self.mCreated.items.len > 0) {
        for (self.mOps.items) |*op| {
            if (self._WasCreated(op.mECS, op.mEntityID)) self._Apply(engine_context, op);
        }
    }
    var created_ind = self.mCreated.items.len;
    while (created_ind > 0) {
        created_ind -= 1;
        const created = self.mCreated.items[created_ind];
        created.mUndo(created.mECS, engine_context, created.mEntityID);
    }

    var op_ind = self.mOps.items.len;
    while (op_ind > 0) {
        op_ind -= 1;
        const op = &self.mOps.items[op_ind];
        if (op.mDone) continue;
        op.mDone = true;
        op.mDrop(op.mECS, engine_context, op);
    }

    for (self.mEntries.items) |entry| entry.mFns.mDiscard(engine_context, entry.mCopy);
    self._Reset(engine_context.EngineAllocator());
}

fn _Apply(_: *Transaction, engine_context: *EngineContext, op: *Op) void {
    if (op.mDone) return;
    op.mDone = true;
    op.mApply(op.mECS, engine_context, op);
}

fn _WasCreated(self: *const Transaction, ecs: *anyopaque, entity_id: u64) bool {
    for (self.mCreated.items) |created| {
        if (created.mECS == ecs and created.mEntityID == entity_id) return true;
    }
    return false;
}

fn _IsEmpty(self: *const Transaction) bool {
    return self.mEntries.items.len == 0 and self.mOps.items.len == 0 and self.mCreated.items.len == 0 and
        self.mOnCommit.items.len == 0 and self.mOnDiscard.items.len == 0 and self.mIrrevocable == null;
}

fn _Reset(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    self.mEngineContext = null;
    self.mEntries.clearRetainingCapacity();
    self.mLookup.clearRetainingCapacity();
    var arena = self.mArena.promote(engine_allocator);
    _ = arena.reset(.retain_capacity);
    self.mArena = arena.state;
    self.mOps.clearRetainingCapacity();
    self.mPresence.clearRetainingCapacity();
    self.mCreated.clearRetainingCapacity();
    self.mOnCommit.clearRetainingCapacity();
    self.mOnDiscard.clearRetainingCapacity();
    self.mIrrevocable = null;
    self.mSpeculating = false;
    self.mRunSerially = false;
    self.mFailed = false;
    self.mMeasuring = false;
    self.mMeasureLost = false;
    self.mReads.clearRetainingCapacity();
    self.mWrites.clearRetainingCapacity();
    self.mTypeReads.clearRetainingCapacity();
    self.mTypeWrites.clearRetainingCapacity();
    self.mNames.clearRetainingCapacity();
    self.mLastNamed = null;
}
