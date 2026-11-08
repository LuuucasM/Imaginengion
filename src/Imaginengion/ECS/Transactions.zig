//! The transactions layer: runs code so that what it does to the ECSs can be kept or dropped as one (RunTransaction),
//! and runs a batch of hooks the way Aria does (RunBatch). Its own layer beside the systems layer, not part of it: a
//! system is a pass, a transaction is how a piece of code's changes are kept apart. The one place the two meet is that a
//! transaction is also a run of the systems layer (engine_context.mSystems), so structural changes wait in it the same
//! way and land after it.
//!
//! Every ECS it knows (Register) points at the transaction open now, and reads and writes through it (Transaction).
const Transactions = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const Transaction = @import("Transaction.zig");
const ConflictReport = @import("ConflictReport.zig");

/// The one transaction RunTransaction uses, kept between uses for its memory
mTransaction: Transaction = .empty,
/// The transaction open now, null otherwise. Every registered ECS points at this, see ECSManager.mTransaction
mOpenTransaction: ?*Transaction = null,
/// The transactions of a batch's hooks (RunBatch), one each, kept between batches for their memory
mBatchPool: std.ArrayList(*Transaction) = .empty,
/// What hooks would have conflicted if each system run's hooks had run in parallel, while measuring (mConflicts.mOn)
mConflicts: ConflictReport = .empty,
/// How many ECSs are registered: the layer lets go of its memory when the last one goes, like the systems layer
mRegistered: usize = 0,

pub const empty: Transactions = .{};

pub fn Deinit(self: *Transactions, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mOpenTransaction == null);
    self.mTransaction.Deinit(engine_allocator);
    self.mConflicts.Deinit(engine_allocator);
    for (self.mBatchPool.items) |transaction| {
        transaction.Deinit(engine_allocator);
        engine_allocator.destroy(transaction);
    }
    self.mBatchPool.deinit(engine_allocator);
    self.mBatchPool = .empty;
}

/// Points `ecs` (a pointer to an ECSManager) at the open transaction, so it reads and writes through it
pub fn Register(self: *Transactions, ecs: anytype) void {
    ecs.SetTransaction(&self.mOpenTransaction);
    self.mRegistered += 1;
}

/// Stops `ecs` going through transactions. Once the last one is gone the layer lets go of its memory too
pub fn Unregister(self: *Transactions, engine_allocator: std.mem.Allocator, ecs: anytype) void {
    ecs.SetTransaction(null);
    self.mRegistered -= 1;
    if (self.mRegistered == 0) self.Deinit(engine_allocator);
}

/// The transaction open now, null outside one: for code outside the ECSs to hold its changes back in
/// (Transaction.OnCommit, OnDiscard)
pub fn OpenTransaction(self: *const Transactions) ?*Transaction {
    return self.mOpenTransaction;
}

/// Says that what the caller is about to do can't be taken back, so an open transaction is kept even if its code fails
/// (Transaction.MarkIrrevocable). Nothing outside a transaction. A speculating one refuses it (error.RunSerially), and
/// the caller mustn't go on to do it
pub fn MarkIrrevocable(self: *const Transactions, reason: []const u8) error{RunSerially}!void {
    if (self.mOpenTransaction) |transaction| try transaction.MarkIrrevocable(reason);
}

/// What `func` returns
pub fn ReturnOf(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

/// Calls `func` with `args` (a tuple) inside a transaction, and hands back what it returns. What it changes in a
/// registered ECS is kept apart or held until it returns (see Transaction): component values, adds, removals, destroys,
/// objects made and tags. Then it is kept when `keep(result)` says so, and dropped otherwise, as if it never happened:
/// the script runner keeps a hook's changes unless the hook failed.
/// A transaction is also a run of the systems layer, so structural changes wait in it the same way, and land after it
/// when it is the outermost run (a failure landing them is logged). Inside a transaction already, `func` is part of that
/// one, and what it changed goes or stays with it.
pub fn RunTransaction(self: *Transactions, engine_context: *EngineContext, comptime func: anytype, args: anytype, comptime keep: anytype) ReturnOf(func) {
    return self._Transact(engine_context, func, args, keep, true);
}

// RunTransaction. `reported`: whether the conflict report checks it, which a batch's hooks run again on their own aren't:
// the batch counts them itself
fn _Transact(self: *Transactions, engine_context: *EngineContext, comptime func: anytype, args: anytype, comptime keep: anytype, reported: bool) ReturnOf(func) {
    if (self.mOpenTransaction != null) return @call(.auto, func, args);

    engine_context.mSystems.EnterRun();
    self.mTransaction.Open(engine_context, .{ .mMeasuring = reported and self.mConflicts.InBatch() });
    self.mOpenTransaction = &self.mTransaction;
    const result = @call(.auto, func, args);
    self.mOpenTransaction = null;

    // still inside the run: what keeping or dropping sets off waits like anything else in it
    const kept = keep(result);
    if (self.mTransaction.mMeasuring) self.mConflicts.Check(engine_context.EngineAllocator(), &self.mTransaction, kept or self.mTransaction.mIrrevocable != null);
    _End(engine_context, &self.mTransaction, kept);

    engine_context.mSystems.LeaveRun(engine_context);
    return result;
}

// keeps or drops a transaction that has just run: one that did something that can't be taken back is kept either way,
// rather than coming out half undone
fn _End(engine_context: *EngineContext, transaction: *Transaction, kept: bool) void {
    if (kept) {
        transaction.Commit(engine_context);
    } else if (transaction.mIrrevocable) |reason| {
        std.log.warn("A failed transaction was kept, since it did something that can't be taken back: {s}", .{reason});
        transaction.Commit(engine_context);
    } else {
        transaction.Discard(engine_context);
    }
}

/// Runs `count` hooks as one batch the way Aria does (transactions plan, step 5). Hook i is `func` called with `args`
/// and then i; i is its place in the batch (Aria's TID), and `keep` says whether what it hands back is kept, as for
/// RunTransaction. Each round has Aria's three phases:
///   1. Execution: every hook still to run speculates in a transaction of its own, against the same state, writing down
///      what it reads and writes. None sees another's changes, and none may do anything for real (Transaction)
///   2. Reservation (ReserveWrite): each hook that ran to the end reserves every key it writes; a key's reservation is
///      the lowest place in the batch that writes it. Hooks that failed or must run on their own reserve nothing
///   3. Commit, in order of place: a hook aborts if anything it read or wrote (RS U WS) was reserved by a hook before it
///      (HasConflicts), and goes to the next round; otherwise it is kept (Install), or dropped if it failed
/// The first hook of a round can't conflict, so each round finishes at least one, and the rounds end. A hook that asked
/// for something that can't be speculative (an object made, something irrevocable) is dropped and run on its own once
/// the rounds are done, in order. No deterministic reordering or fallback, and one thread for now: every hook runs on the
/// caller's, and installs go in order so the ECS queues fill the same way every time.
/// A hook that aborted runs after those kept before it, so the result is the one running them in some order would give,
/// the same every time, though not always the list's own order. Inside a transaction already, the hooks are run one
/// after another as part of it
pub fn RunBatch(self: *Transactions, engine_context: *EngineContext, count: usize, comptime func: anytype, args: anytype, comptime keep: anytype) !void {
    if (self.mOpenTransaction != null) {
        for (0..count) |index| _ = @call(.auto, func, args ++ .{index});
        return;
    }
    if (count == 0) return;
    const zone = Tracy.ZoneInit("Transactions::RunBatch", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();
    const results = try engine_allocator.alloc(ReturnOf(func), count);
    defer engine_allocator.free(results);
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(engine_allocator);
    var next: std.ArrayList(usize) = .empty;
    defer next.deinit(engine_allocator);
    var serial: std.ArrayList(usize) = .empty;
    defer serial.deinit(engine_allocator);
    var reservations: Transaction.Reservations = .{};
    defer reservations.Deinit(engine_allocator);

    try pending.ensureTotalCapacity(engine_allocator, count);
    try next.ensureTotalCapacity(engine_allocator, count);
    try serial.ensureTotalCapacity(engine_allocator, count);
    for (0..count) |index| pending.appendAssumeCapacity(index);
    while (self.mBatchPool.items.len < count) {
        const transaction = try engine_allocator.create(Transaction);
        transaction.* = .empty;
        self.mBatchPool.append(engine_allocator, transaction) catch |err| {
            engine_allocator.destroy(transaction);
            return err;
        };
    }

    engine_context.mSystems.EnterRun();
    defer engine_context.mSystems.LeaveRun(engine_context);

    var round: usize = 0;
    while (pending.items.len > 0) : (round += 1) {
        const round_zone = Tracy.ZoneInit("Transactions::RunBatch round", @src());
        defer round_zone.Deinit();
        round_zone.Value(pending.items.len);

        // 1. execution
        for (pending.items, 0..) |index, slot| {
            const transaction = self.mBatchPool.items[slot];
            transaction.Open(engine_context, .{ .mMeasuring = true, .mSpeculating = true });
            self.mOpenTransaction = transaction;
            results[index] = @call(.auto, func, args ++ .{index});
            self.mOpenTransaction = null;
        }

        // 2. reservation. A reservation that couldn't be written down (out of memory) leaves the round unable to tell
        // who conflicts, so all but its first hook go again
        reservations.Clear();
        var reservations_lost = false;
        for (pending.items, 0..) |index, slot| {
            const transaction = self.mBatchPool.items[slot];
            if (transaction.mRunSerially or !keep(results[index])) continue;
            reservations.Reserve(engine_allocator, transaction, index) catch {
                reservations_lost = true;
            };
        }

        // 3. commit, in order
        next.clearRetainingCapacity();
        for (pending.items, 0..) |index, slot| {
            const transaction = self.mBatchPool.items[slot];
            if (transaction.mRunSerially) {
                self.mConflicts.CountBatchHook(engine_allocator, .Serial, "");
                transaction.Discard(engine_context);
                serial.appendAssumeCapacity(index);
                continue;
            }
            const first = slot == 0;
            const conflict = transaction.ConflictWith(&reservations, index);
            if (!first and (reservations_lost or transaction.mMeasureLost or conflict != null)) {
                self.mConflicts.CountBatchHook(engine_allocator, .Conflict, if (conflict) |array| transaction.NameOf(array) else "");
                transaction.Discard(engine_context);
                next.appendAssumeCapacity(index);
                continue;
            }
            self.mConflicts.CountBatchHook(engine_allocator, .Done, "");
            if (keep(results[index])) transaction.Commit(engine_context) else transaction.Discard(engine_context);
        }
        std.mem.swap(std.ArrayList(usize), &pending, &next);
    }
    zone.Value(round);

    for (serial.items) |index| {
        _ = self._Transact(engine_context, func, args ++ .{index}, keep, false);
        self.mConflicts.CountBatchHook(engine_allocator, .Done, "");
    }
}
