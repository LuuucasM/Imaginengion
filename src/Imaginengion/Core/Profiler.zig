//! The engine's own measuring: how long each zone takes (Tracy.ZoneInit), as a tree of where it was called from. A
//! node is "this zone, inside that one", so the same function called from two places is two nodes, and the tree is the
//! shape of the loop: Main Loop, then what it calls, then what they call. Each node adds up its time and calls over a
//! pass of the loop, and EndLoop keeps them, one entry a loop, for the last HISTORY loops, which Summarize reads.
//!
//! Only the thread that started it is measured; zones on any other thread are left out. Everything it keeps is one
//! allocation made in Start, so measuring a zone never allocates. Zones never seen before are added as they are met,
//! until MAX_NODES; past that, and past MAX_DEPTH zones deep, a zone's time goes to the zone it is inside.
//!
//! Script DLLs compile their own copy of this file with a gMain of their own that is never started, so their zones
//! cost a check and nothing more.
const std = @import("std");
const CircularHistory = @import("CircularHistory.zig").CircularHistory;

const Profiler = @This();

pub const NodeIndex = u16;
pub const MAX_NODES = 1024;
/// How many passes of the loop each node remembers
pub const HISTORY = 1024;
pub const MAX_DEPTH = 64;
/// The node every zone not inside another hangs off. Measures nothing itself
pub const ROOT: NodeIndex = 0;
pub const NONE: NodeIndex = std.math.maxInt(NodeIndex);

/// The one the engine's zones measure into (Tracy.ZoneInit)
pub var gMain: Profiler = .{};

/// One place in the code that starts a zone: ZoneInit keeps one per call site, so a node is told apart by which Site
/// it is. Changed only by the measured thread
pub const Site = struct {
    mName: [:0]const u8,
    /// the node this site was last measured as, to skip looking it up when it is called from the same place again
    mLastNode: NodeIndex = NONE,
};

pub const Node = struct {
    mSite: *Site,
    mParent: NodeIndex,
    mFirstChild: NodeIndex = NONE,
    mNextSibling: NodeIndex = NONE,
    /// this pass of the loop so far
    mNanoseconds: u64 = 0,
    mCalls: u32 = 0,
};

/// A zone that has started and not ended yet
const Open = struct {
    mNode: NodeIndex,
    mStart: u64,
};

/// Each node's history, a pass of the loop an entry: its time in nanoseconds (a pass over 4 seconds is kept as 4
/// seconds) and how many times it ran (likewise kept under 65536)
pub const Times = CircularHistory(u32, HISTORY);
pub const Calls = CircularHistory(u16, HISTORY);

const Storage = struct {
    mNodes: [MAX_NODES]Node,
    mTimes: [MAX_NODES]Times,
    mCalls: [MAX_NODES]Calls,
    mStack: [MAX_DEPTH]Open,
};

mStorage: ?*Storage = null,
mIo: std.Io = undefined,
mAllocator: std.mem.Allocator = undefined,
mThread: std.Thread.Id = undefined,
mNodeCount: NodeIndex = 0,
mDepth: u8 = 0,
/// zones begun while MAX_DEPTH were already open: not measured, only counted so their ends are matched
mTooDeep: u32 = 0,
/// passes of the loop ended since Start
mLoops: u64 = 0,

/// Starts measuring the calling thread's zones, with `io`'s clock
pub fn Start(self: *Profiler, allocator: std.mem.Allocator, io: std.Io) !void {
    std.debug.assert(self.mStorage == null);
    const storage = try allocator.create(Storage);
    storage.mNodes[ROOT] = .{ .mSite = &root_site, .mParent = NONE };
    storage.mTimes[ROOT] = .empty;
    storage.mCalls[ROOT] = .empty;
    self.* = .{
        .mStorage = storage,
        .mIo = io,
        .mAllocator = allocator,
        .mThread = std.Thread.getCurrentId(),
        .mNodeCount = 1,
    };
}

/// Stops measuring and lets go of everything kept. Zones still open end without being measured
pub fn Stop(self: *Profiler) void {
    const storage = self.mStorage orelse return;
    self.mStorage = null;
    self.mAllocator.destroy(storage);
    self.* = .{};
}

pub fn IsRunning(self: *const Profiler) bool {
    return self.mStorage != null;
}

var root_site: Site = .{ .mName = "Root" };

/// A zone at `site` starts. False when it isn't measured (not started, another thread), and then End mustn't be called
pub fn Begin(self: *Profiler, site: *Site) bool {
    const storage = self.mStorage orelse return false;
    if (std.Thread.getCurrentId() != self.mThread) return false;
    if (self.mDepth == MAX_DEPTH) {
        self.mTooDeep += 1;
        return true;
    }
    const parent = if (self.mDepth == 0) ROOT else storage.mStack[self.mDepth - 1].mNode;
    storage.mStack[self.mDepth] = .{ .mNode = self.NodeFor(storage, parent, site), .mStart = self.Now() };
    self.mDepth += 1;
    return true;
}

/// The zone begun last ends
pub fn End(self: *Profiler) void {
    const storage = self.mStorage orelse return;
    if (self.mTooDeep > 0) {
        self.mTooDeep -= 1;
        return;
    }
    if (self.mDepth == 0) return;
    self.mDepth -= 1;
    const open = storage.mStack[self.mDepth];
    const node = &storage.mNodes[open.mNode];
    node.mCalls += 1;
    if (!IsFolded(storage, self.mDepth)) node.mNanoseconds += self.Now() -| open.mStart;
}

/// Once at the end of each pass of the loop: every node's time and calls this pass go into its history, and start
/// again from nothing. A zone still open has the time it has run so far put in this pass, the rest in the next
pub fn EndLoop(self: *Profiler) void {
    const storage = self.mStorage orelse return;
    if (self.mDepth > 0) {
        const now = self.Now();
        for (storage.mStack[0..self.mDepth], 0..) |*open, depth| {
            if (!IsFolded(storage, depth)) storage.mNodes[open.mNode].mNanoseconds += now -| open.mStart;
            open.mStart = now;
        }
    }
    for (storage.mNodes[1..self.mNodeCount], storage.mTimes[1..self.mNodeCount], storage.mCalls[1..self.mNodeCount]) |*node, *times, *calls| {
        times.append(@intCast(@min(node.mNanoseconds, std.math.maxInt(u32))));
        calls.append(@intCast(@min(node.mCalls, std.math.maxInt(u16))));
        node.mNanoseconds = 0;
        node.mCalls = 0;
    }
    self.mLoops += 1;
}

/// How many passes of the loop the nodes met from the start remember: HISTORY once that many have ended
pub fn LoopsKept(self: *const Profiler) usize {
    return @intCast(@min(self.mLoops, HISTORY));
}

/// How many nodes there are, the root included. Nodes are never removed, and a node's parent always comes before it
pub fn NodeCount(self: *const Profiler) NodeIndex {
    return self.mNodeCount;
}

pub fn GetNode(self: *const Profiler, node: NodeIndex) *const Node {
    return &self.mStorage.?.mNodes[node];
}

pub fn Name(self: *const Profiler, node: NodeIndex) [:0]const u8 {
    return self.GetNode(node).mSite.mName;
}

/// A node's history, to put entries in by hand (tests) or read them
pub fn History(self: *const Profiler, node: NodeIndex) struct { Times: *Times, Calls: *Calls } {
    const storage = self.mStorage.?;
    return .{ .Times = &storage.mTimes[node], .Calls = &storage.mCalls[node] };
}

/// The nodes directly under `node`, in the order they were first met
pub fn Children(self: *const Profiler, node: NodeIndex) ChildIterator {
    return .{ .mProfiler = self, .mNext = self.GetNode(node).mFirstChild };
}

pub const ChildIterator = struct {
    mProfiler: *const Profiler,
    mNext: NodeIndex,

    pub fn next(self: *ChildIterator) ?NodeIndex {
        if (self.mNext == NONE) return null;
        const child = self.mNext;
        self.mNext = self.mProfiler.GetNode(child).mNextSibling;
        return child;
    }
};

/// A node over the loops it remembers. Avg, P99 and Max are per pass of the loop, counting passes it didn't run in
pub const Summary = struct {
    Avg: std.Io.Duration = .zero,
    /// 99 in 100 passes took no longer than this
    P99: std.Io.Duration = .zero,
    Max: std.Io.Duration = .zero,
    /// times it ran a pass, on average
    Calls: f32 = 0,
    /// how many passes this is over
    Loops: usize = 0,
};

/// A node's average a pass of the loop alone, which is all a parent needs of its children to work out its own time
pub fn Average(self: *const Profiler, node: NodeIndex) std.Io.Duration {
    const times = self.History(node).Times.items();
    if (times.len == 0) return .zero;
    var total: u64 = 0;
    for (times) |time| total += time;
    return .fromNanoseconds(@divFloor(total, times.len));
}

pub fn Summarize(self: *const Profiler, node: NodeIndex) Summary {
    const history = self.History(node);
    return SummarizeHistory(history.Times.items(), history.Calls.items());
}

/// The summary of a node's history: `times` in nanoseconds and `calls`, a pass of the loop an entry, in any order
pub fn SummarizeHistory(times: []const u32, calls: []const u16) Summary {
    if (times.len == 0) return .{};
    var total: u64 = 0;
    for (times) |time| total += time;
    var total_calls: u64 = 0;
    for (calls) |count| total_calls += count;
    const loops: f32 = @floatFromInt(times.len);
    return .{
        .Avg = .fromNanoseconds(@divFloor(total, times.len)),
        .P99 = .fromNanoseconds(Largest(times, times.len / 100 + 1)),
        .Max = .fromNanoseconds(Largest(times, 1)),
        .Calls = @as(f32, @floatFromInt(total_calls)) / loops,
        .Loops = times.len,
    };
}

/// The `rank`th largest of `values` (1 is the largest). Keeps only the largest `rank` seen so far, so it is one pass
/// over them rather than a sort: the panel summarizes every open node a few times a second, and a sort each would show
/// up in the passes that do it
fn Largest(values: []const u32, rank: usize) u32 {
    var top: [HISTORY / 100 + 1]u32 = undefined;
    const kept = @min(rank, top.len, values.len);
    var count: usize = 0;
    for (values) |value| {
        if (count == kept and value <= top[kept - 1]) continue;
        //largest first: slide the smaller ones down a place, dropping the last when full
        var at = if (count < kept) count else kept - 1;
        while (at > 0 and top[at - 1] < value) : (at -= 1) top[at] = top[at - 1];
        top[at] = value;
        if (count < kept) count += 1;
    }
    return top[kept - 1];
}

// the node `site` is when called from inside `parent`: the one it was last time if it was called from there then,
// otherwise looked for among the parent's children, otherwise added. A site inside itself is measured as the outer
// one (folded), and with no room left a site is folded into its parent
fn NodeFor(self: *Profiler, storage: *Storage, parent: NodeIndex, site: *Site) NodeIndex {
    if (parent != ROOT and storage.mNodes[parent].mSite == site) return parent;
    if (site.mLastNode < self.mNodeCount) {
        const last = storage.mNodes[site.mLastNode];
        if (last.mSite == site and last.mParent == parent) return site.mLastNode;
    }
    var child = storage.mNodes[parent].mFirstChild;
    var last_child = NONE;
    while (child != NONE) : (child = storage.mNodes[child].mNextSibling) {
        if (storage.mNodes[child].mSite == site) {
            site.mLastNode = child;
            return child;
        }
        last_child = child;
    }
    if (self.mNodeCount == MAX_NODES) return parent;

    const node = self.mNodeCount;
    self.mNodeCount += 1;
    storage.mNodes[node] = .{ .mSite = site, .mParent = parent };
    storage.mTimes[node] = .empty;
    storage.mCalls[node] = .empty;
    if (last_child == NONE) storage.mNodes[parent].mFirstChild = node else storage.mNodes[last_child].mNextSibling = node;
    site.mLastNode = node;
    return node;
}

// whether the zone open at `depth` is measured as one outside it (the same node as the one it is inside, or the root),
// so its time is already in there and isn't added again
fn IsFolded(storage: *const Storage, depth: usize) bool {
    const node = storage.mStack[depth].mNode;
    return node == ROOT or (depth > 0 and storage.mStack[depth - 1].mNode == node);
}

fn Now(self: *const Profiler) u64 {
    return @intCast(std.Io.Timestamp.now(self.mIo, .awake).toNanoseconds());
}
