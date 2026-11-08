//! What hooks would have conflicted if each batch had run in parallel (transactions plan, step 4), measured while
//! everything still runs one after another. Nothing about how anything runs changes.
//!
//! A batch is the transactions one system run makes directly: every script loop is a system and every hook in it a
//! transaction. While measuring, the systems layer pushes a batch for each RunSystem and pops it when the run ends, and
//! each outermost transaction, as it ends, is checked against its run's batch (Check), by Aria's rule: it would conflict
//! if something it read was written by a kept hook before it in the same batch. One that conflicts would be run again
//! after the batch, and one that made an object or did something irrevocable would run on its own after it (step 5's
//! rule), so neither one's writes count against the rest. A failed hook's writes were dropped, so they don't count either.
//! What each transaction read and wrote is written down by the ECSs (Transaction.NoteRead and the rest).
const ConflictReport = @This();

const std = @import("std");
const Transaction = @import("Transaction.zig");

/// Measuring on: transactions in a batch write down what they read and write. Off by default
mOn: bool = false,
/// The batches of the runs going on, innermost last. Only the first mDepth are in use; the rest keep their memory
mBatches: std.ArrayList(Batch) = .empty,
mDepth: usize = 0,
/// What has been found, by system name (each name the report's own copy)
mSystems: std.StringArrayHashMapUnmanaged(Counts) = .empty,

pub const empty: ConflictReport = .{};

/// One run's batch, while it goes on
const Batch = struct {
    mName: []const u8 = "",
    /// What the batch's kept hooks have written, so far
    mWritten: Transaction.WriteSet = .{},
    mCounts: Counts = .{},
    /// Writing down a hook's writes failed (out of memory): the batch's counts aren't kept
    mLost: bool = false,
};

/// What measuring found for one system
pub const Counts = struct {
    /// runs of it that had at least one hook
    mBatches: u64 = 0,
    mHooks: u64 = 0,
    /// hooks that read something an earlier kept hook in their batch wrote
    mConflicts: u64 = 0,
    /// hooks that made an object or did something irrevocable, which would run on their own
    mSerial: u64 = 0,
    /// hooks that couldn't be measured (out of memory)
    mLost: u64 = 0,
    /// which type each conflict was on, by type name (the report's own copies)
    mTypes: std.StringArrayHashMapUnmanaged(u64) = .empty,
};

pub fn Deinit(self: *ConflictReport, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mDepth == 0);
    for (self.mBatches.items) |*batch| batch.mWritten.Deinit(engine_allocator);
    self.mBatches.deinit(engine_allocator);
    self.Clear(engine_allocator);
    self.mSystems.deinit(engine_allocator);
    self.* = .empty;
}

/// Forgets what has been found
pub fn Clear(self: *ConflictReport, engine_allocator: std.mem.Allocator) void {
    for (self.mSystems.keys(), self.mSystems.values()) |name, *counts| {
        for (counts.mTypes.keys()) |type_name| engine_allocator.free(type_name);
        counts.mTypes.deinit(engine_allocator);
        engine_allocator.free(name);
    }
    self.mSystems.clearRetainingCapacity();
}

/// Whether a transaction opening now is in a batch that is being measured
pub fn InBatch(self: *const ConflictReport) bool {
    return self.mDepth > 0;
}

/// Starts the batch of a run of the system `name`, if measuring is on. Whether it did, for PopBatch
pub fn PushBatch(self: *ConflictReport, engine_allocator: std.mem.Allocator, name: []const u8) bool {
    if (!self.mOn) return false;
    if (self.mDepth == self.mBatches.items.len) {
        self.mBatches.append(engine_allocator, .{}) catch return false;
    }
    const batch = &self.mBatches.items[self.mDepth];
    batch.mName = name;
    batch.mWritten.Clear();
    batch.mCounts = .{};
    batch.mLost = false;
    self.mDepth += 1;
    return true;
}

/// Ends the innermost batch, adding what it found to the report
pub fn PopBatch(self: *ConflictReport, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mDepth > 0);
    self.mDepth -= 1;
    const batch = &self.mBatches.items[self.mDepth];
    if (batch.mCounts.mHooks == 0) return;
    const counts = self._CountsOf(engine_allocator, batch.mName) orelse return;
    counts.mBatches += 1;
    counts.mHooks += batch.mCounts.mHooks;
    counts.mConflicts += batch.mCounts.mConflicts;
    counts.mSerial += batch.mCounts.mSerial;
    counts.mLost += batch.mCounts.mLost;
    if (batch.mLost) counts.mLost += 1;
}

/// Checks an outermost transaction that has just ended against its run's batch, before it is kept or dropped. `kept`:
/// whether it will be kept
pub fn Check(self: *ConflictReport, engine_allocator: std.mem.Allocator, transaction: *const Transaction, kept: bool) void {
    if (self.mDepth == 0) return;
    const batch = &self.mBatches.items[self.mDepth - 1];
    batch.mCounts.mHooks += 1;

    if (transaction.mMeasureLost) {
        batch.mCounts.mLost += 1;
        return;
    }
    if (transaction.mCreated.items.len > 0 or transaction.mIrrevocable != null) {
        batch.mCounts.mSerial += 1;
        return;
    }
    if (transaction.ConflictOn(&batch.mWritten)) |array| {
        batch.mCounts.mConflicts += 1;
        self._CountType(engine_allocator, batch.mName, transaction.NameOf(array));
        return;
    }
    if (!kept) return;
    batch.mWritten.Add(engine_allocator, transaction) catch {
        batch.mLost = true;
    };
}

/// How a hook of a real batch (Transactions.RunBatch) came out in one round
pub const BatchOutcome = enum {
    /// ran to the end, kept or failed
    Done,
    /// read what a hook kept before it wrote: run again in the next round
    Conflict,
    /// asked for something that can't be speculative: run on its own after the rounds
    Serial,
};

/// Counts a hook of a real batch in the run it is in, while measuring: each conflict it had on the way, and the hook
/// itself once it is done. `type_name`: for a conflict, what it was on
pub fn CountBatchHook(self: *ConflictReport, engine_allocator: std.mem.Allocator, outcome: BatchOutcome, type_name: []const u8) void {
    if (self.mDepth == 0) return;
    const batch = &self.mBatches.items[self.mDepth - 1];
    switch (outcome) {
        .Done => batch.mCounts.mHooks += 1,
        .Serial => batch.mCounts.mSerial += 1,
        .Conflict => {
            batch.mCounts.mConflicts += 1;
            if (type_name.len > 0) self._CountType(engine_allocator, batch.mName, type_name);
        },
    }
}

// the counts for a system, made the first time with a copy of its name. Null if there was no room
fn _CountsOf(self: *ConflictReport, engine_allocator: std.mem.Allocator, name: []const u8) ?*Counts {
    const entry = self.mSystems.getOrPut(engine_allocator, name) catch return null;
    if (!entry.found_existing) {
        entry.key_ptr.* = engine_allocator.dupe(u8, name) catch {
            _ = self.mSystems.swapRemove(name);
            return null;
        };
        entry.value_ptr.* = .{};
    }
    return entry.value_ptr;
}

fn _CountType(self: *ConflictReport, engine_allocator: std.mem.Allocator, system_name: []const u8, type_name: []const u8) void {
    const counts = self._CountsOf(engine_allocator, system_name) orelse return;
    const entry = counts.mTypes.getOrPut(engine_allocator, type_name) catch return;
    if (!entry.found_existing) {
        entry.key_ptr.* = engine_allocator.dupe(u8, type_name) catch {
            _ = counts.mTypes.swapRemove(type_name);
            return;
        };
        entry.value_ptr.* = 0;
    }
    entry.value_ptr.* += 1;
}
