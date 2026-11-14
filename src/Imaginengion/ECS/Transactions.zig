//! The transactions layer: runs code so that what it does to the ECSs can be kept or dropped as one (RunTransaction),
//! and runs a batch of hooks the way Aria does (RunBatch). Its own layer beside the systems layer, not part of it: a
//! system is a pass, a transaction is how a piece of code's changes are kept apart. The one place the two meet is that a
//! transaction is also a run of the systems layer (engine_context.mSystems), so structural changes wait in it the same
//! way and land after it.
//!
//! Every ECS it knows (Register) asks it for the transaction open now (Current), and reads and writes through it
//! (Transaction). Outside a batch's parallel execution phase that is the one open transaction (mOpenTransaction).
//! During one, each thread running a hook has its own: kept in a threadlocal of the engine's, read and set through
//! function pointers the engine fills in (mCurrentFn, mSetCurrentFn), since a script DLL's copy of this code has a
//! threadlocal of its own that the engine never sets.
const Transactions = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const Transaction = @import("Transaction.zig");
const ConflictReport = @import("ConflictReport.zig");
const JobGroup = @import("../Core/JobGroup.zig");

/// The one transaction RunTransaction uses, kept between uses for its memory
mTransaction: Transaction = .empty,
/// The transaction open now outside a parallel execution phase, null otherwise. Read through Current
mOpenTransaction: ?*Transaction = null,
/// A batch's execution phase is going on (RunBatch): each thread running a hook has its own transaction (Current)
mParallel: bool = false,
/// The calling thread's transaction during a parallel execution phase, and setting it: the engine's own functions,
/// filled in when the context is made, so every copy of the engine code reads the engine's threadlocal
mCurrentFn: *const fn () ?*Transaction = &_CurrentOnThisThread,
mSetCurrentFn: *const fn (?*Transaction) void = &_SetCurrentOnThisThread,
/// The transactions of a batch's hooks (RunBatch), one each, kept between batches for their memory
mBatchPool: std.ArrayList(*Transaction) = .empty,
/// What hooks would have conflicted if each system run's hooks had run in parallel, while measuring (mConflicts.mOn)
mConflicts: ConflictReport = .empty,
/// How many ECSs are registered: the layer lets go of its memory when the last one goes, like the systems layer
mRegistered: usize = 0,

pub const empty: Transactions = .{};

/// The calling thread's transaction during a parallel execution phase (see mCurrentFn). Only ever read and set through
/// the function pointers, so only the engine's copy is used
threadlocal var tCurrent: ?*Transaction = null;

fn _CurrentOnThisThread() ?*Transaction {
    return tCurrent;
}

fn _SetCurrentOnThisThread(transaction: ?*Transaction) void {
    tCurrent = transaction;
}

pub fn Deinit(self: *Transactions, keep_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mOpenTransaction == null);
    self.mTransaction.Deinit(keep_allocator);
    self.mConflicts.Deinit(keep_allocator);
    for (self.mBatchPool.items) |transaction| {
        transaction.Deinit(keep_allocator);
        keep_allocator.destroy(transaction);
    }
    self.mBatchPool.deinit(keep_allocator);
    self.mBatchPool = .empty;
}

/// Points `ecs` (a pointer to an ECSManager) at this layer, so it reads and writes through the transaction open now
pub fn Register(self: *Transactions, ecs: anytype) void {
    ecs.SetTransactions(self);
    self.mRegistered += 1;
}

/// Stops `ecs` going through transactions. Once the last one is gone the layer lets go of its memory too
pub fn Unregister(self: *Transactions, keep_allocator: std.mem.Allocator, ecs: anytype) void {
    ecs.SetTransactions(null);
    self.mRegistered -= 1;
    if (self.mRegistered == 0) self.Deinit(keep_allocator);
}

/// The transaction open now on the calling thread, null outside one: what the ECSs read and write through
pub fn Current(self: *const Transactions) ?*Transaction {
    // outside a parallel execution phase, the one open transaction: no call, the same cost as before threads
    if (!self.mParallel) return self.mOpenTransaction;
    return self.mCurrentFn();
}

/// Refuses something a hook speculating in a batch mustn't do on the calling thread (Transaction.RefuseSpeculative):
/// the error to refuse with, and the hook runs again on its own. Null when it can go ahead
pub fn RefuseSpeculative(self: *const Transactions) ?error{RunSerially} {
    const transaction = self.Current() orelse return null;
    return transaction.RefuseSpeculative();
}

/// In safe builds, panics if the calling thread is running a hook of a batch's parallel execution phase: for what only
/// the main thread may do, `what` saying what that was. The check that finds what still needs refusing or making safe
pub fn CheckMainThread(self: *const Transactions, comptime what: []const u8) void {
    if (!std.debug.runtime_safety) return;
    if (self.OnWorker()) std.debug.panic(what ++ " from a hook running in a batch, which only the main thread may do", .{});
}

/// Whether the calling thread is running a hook of a batch's parallel execution phase. A run started there (a hook
/// running a system) leaves the run depth and the conflict report alone: the batch's own run holds everything
pub fn OnWorker(self: *const Transactions) bool {
    return self.mParallel and self.mCurrentFn() != null;
}

/// The transaction open now, null outside one: for code outside the ECSs to hold its changes back in
/// (Transaction.OnCommit, OnDiscard)
pub fn OpenTransaction(self: *const Transactions) ?*Transaction {
    return self.Current();
}

/// Says that what the caller is about to do can't be taken back, so an open transaction is kept even if its code fails
/// (Transaction.MarkIrrevocable). Nothing outside a transaction. A speculating one refuses it (error.RunSerially), and
/// the caller mustn't go on to do it
pub fn MarkIrrevocable(self: *const Transactions, reason: []const u8) error{RunSerially}!void {
    if (self.Current()) |transaction| try transaction.MarkIrrevocable(reason);
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
    if (self.Current() != null) return @call(.auto, func, args);

    engine_context.mSystems.EnterRun(engine_context);
    self.mTransaction.Open(engine_context, .{ .mMeasuring = reported and self.mConflicts.InBatch() });
    self.mOpenTransaction = &self.mTransaction;
    const result = @call(.auto, func, args);
    self.mOpenTransaction = null;

    // still inside the run: what keeping or dropping sets off waits like anything else in it. Code that said it failed
    // (MarkFailed) isn't kept whatever it handed back
    const kept = keep(result) and !self.mTransaction.mFailed;
    if (self.mTransaction.mMeasuring) self.mConflicts.Check(engine_context.Keep(), &self.mTransaction, kept or self.mTransaction.mIrrevocable != null);
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

/// Says that what the task running on the calling thread was for didn't happen (a hook that failed or hit an error):
/// its transaction is dropped rather than kept. For tasks of an AriaIo group, which hand nothing back
pub fn MarkFailed(self: *const Transactions) void {
    if (self.Current()) |transaction| transaction.mFailed = true;
}

/// Runs `count` hooks as one batch, through an Io.Group on the engine's AriaIo (RunTasks): hook i is `func` called with
/// `args` and then i, and `keep` says whether what it hands back is kept, as for RunTransaction
pub fn RunBatch(self: *Transactions, engine_context: *EngineContext, count: usize, comptime func: anytype, args: anytype, comptime keep: anytype) !void {
    _ = self;
    const Args = @TypeOf(args);
    const Hook = struct {
        fn Run(context: *EngineContext, call_args: Args, index: usize) void {
            const result = @call(.auto, func, call_args ++ .{index});
            if (!keep(result)) context.mTransactions.MarkFailed();
        }
    };
    const aria = engine_context.AriaIo();
    var group: std.Io.Group = .init;
    for (0..count) |index| group.async(aria, Hook.Run, .{ engine_context, args, index });
    try group.await(aria);
}

/// AriaIo's groupAwait: runs the group's queued tasks as a batch (RunTasks)
pub fn AriaGroupAwait(userdata: ?*anyopaque, group: *std.Io.Group, token: *anyopaque) std.Io.Cancelable!void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(userdata.?));
    const job_group: *JobGroup = @ptrCast(@alignCast(token));
    engine_context.mTransactions.RunTasks(engine_context, job_group.mTasks.items) catch |err| {
        std.log.err("A batch of transactions couldn't run: {s}", .{@errorName(err)});
    };
    job_group.Free(engine_context.Keep(), group);
}

/// Runs `tasks` as one batch the way Aria does (transactions plan, step 5): what an AriaIo group's await does. A task's
/// place in the list is Aria's TID; one that fails says so with MarkFailed, and is dropped rather than kept. Each round
/// has Aria's three phases:
///   1. Execution: every task still to run speculates in a transaction of its own, against the same state, writing down
///      what it reads and writes, on the engine's job pool and the calling thread together (JobGroup.ParallelFor). None
///      sees another's changes, and none may do anything for real (Transaction)
///   2. Reservation (ReserveWrite): each task that ran to the end reserves every key it writes; a key's reservation is
///      the lowest place in the batch that writes it. Tasks that failed or must run on their own reserve nothing
///   3. Commit, in order of place: a task aborts if anything it read or wrote (RS U WS) was reserved by one before it
///      (HasConflicts), and goes to the next round; otherwise it is kept (Install), or dropped if it failed
/// The first task of a round can't conflict, so each round finishes at least one, and the rounds end. A task that asked
/// for something that can't be speculative (an object made, something irrevocable) is dropped and run on its own once
/// the rounds are done, in order. No deterministic reordering or fallback. Reservation and commit stay on the calling
/// thread, and installs go in order, so the ECS queues fill the same way every time and the result is the same on any
/// number of threads. A task that aborted runs after those kept before it, so the result is the one running them in some
/// order would give, though not always the list's own order. Inside a transaction already, the tasks run one after
/// another as part of it
pub fn RunTasks(self: *Transactions, engine_context: *EngineContext, tasks: []const JobGroup.Task) !void {
    if (self.Current()) |outer| {
        // part of the transaction already open: a failure of one of these isn't the outer one's
        const outer_failed = outer.mFailed;
        for (tasks) |task| {
            task.Run();
            outer.mFailed = outer_failed;
        }
        return;
    }
    const count = tasks.len;
    if (count == 0) return;
    const zone = Tracy.ZoneInit("Transactions::RunTasks", @src());
    defer zone.Deinit();

    const keep_allocator = engine_context.Keep();
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(keep_allocator);
    var next: std.ArrayList(usize) = .empty;
    defer next.deinit(keep_allocator);
    var serial: std.ArrayList(usize) = .empty;
    defer serial.deinit(keep_allocator);
    var reservations: Transaction.Reservations = .{};
    defer reservations.Deinit(keep_allocator);

    try pending.ensureTotalCapacity(keep_allocator, count);
    try next.ensureTotalCapacity(keep_allocator, count);
    try serial.ensureTotalCapacity(keep_allocator, count);
    for (0..count) |index| pending.appendAssumeCapacity(index);
    while (self.mBatchPool.items.len < count) {
        const transaction = try keep_allocator.create(Transaction);
        transaction.* = .empty;
        self.mBatchPool.append(keep_allocator, transaction) catch |err| {
            keep_allocator.destroy(transaction);
            return err;
        };
    }

    engine_context.mSystems.EnterRun(engine_context);
    defer engine_context.mSystems.LeaveRun(engine_context);

    // what one round's execution needs, on whichever thread runs a task
    const Execution = struct {
        mTransactions: *Transactions,
        mEngineContext: *EngineContext,
        mTasks: []const JobGroup.Task,
        mPending: []const usize,

        // one task speculating: slot is its place in this round, which picks its transaction from the pool
        fn Speculate(execution: *const @This(), slot: usize) void {
            const transaction = execution.mTransactions.mBatchPool.items[slot];
            transaction.Open(execution.mEngineContext, .{ .mMeasuring = true, .mSpeculating = true });
            execution.mTransactions.mSetCurrentFn(transaction);
            defer execution.mTransactions.mSetCurrentFn(null);
            execution.mTasks[execution.mPending[slot]].Run();
        }
    };

    var round: usize = 0;
    while (pending.items.len > 0) : (round += 1) {
        const round_zone = Tracy.ZoneInit("Transactions::RunTasks round", @src());
        defer round_zone.Deinit();
        round_zone.Value(pending.items.len);

        // 1. execution: every task is queued first, then the pool's workers and this thread take them until none is
        // left. Each finds its own transaction through the per-thread lookup (Current)
        const execution = Execution{ .mTransactions = self, .mEngineContext = engine_context, .mTasks = tasks, .mPending = pending.items };
        self.mParallel = true;
        JobGroup.ParallelFor(engine_context.mJobPool, pending.items.len, &execution, Execution.Speculate);
        self.mParallel = false;

        // 2. reservation. A reservation that couldn't be written down (out of memory) leaves the round unable to tell
        // who conflicts, so all but its first task go again
        reservations.Clear();
        var reservations_lost = false;
        for (pending.items, 0..) |index, slot| {
            const transaction = self.mBatchPool.items[slot];
            if (transaction.mRunSerially or transaction.mFailed) continue;
            reservations.Reserve(keep_allocator, transaction, index) catch {
                reservations_lost = true;
            };
        }

        // 3. commit, in order
        next.clearRetainingCapacity();
        for (pending.items, 0..) |index, slot| {
            const transaction = self.mBatchPool.items[slot];
            if (transaction.mRunSerially) {
                self.mConflicts.CountBatchHook(keep_allocator, .Serial, "");
                transaction.Discard(engine_context);
                serial.appendAssumeCapacity(index);
                continue;
            }
            const first = slot == 0;
            const conflict = transaction.ConflictWith(&reservations, index);
            if (!first and (reservations_lost or transaction.mMeasureLost or conflict != null)) {
                self.mConflicts.CountBatchHook(keep_allocator, .Conflict, if (conflict) |array| transaction.NameOf(array) else "");
                transaction.Discard(engine_context);
                next.appendAssumeCapacity(index);
                continue;
            }
            self.mConflicts.CountBatchHook(keep_allocator, .Done, "");
            if (transaction.mFailed) transaction.Discard(engine_context) else transaction.Commit(engine_context);
        }
        std.mem.swap(std.ArrayList(usize), &pending, &next);
    }
    zone.Value(round);

    for (serial.items) |index| {
        _ = self._Transact(engine_context, JobGroup.Task.Run, .{tasks[index]}, _KeepUnlessFailed, false);
        self.mConflicts.CountBatchHook(keep_allocator, .Done, "");
    }
}

// a task hands nothing back: whether it is kept is only whether it said it failed (MarkFailed, checked in _Transact)
fn _KeepUnlessFailed(_: void) bool {
    return true;
}
