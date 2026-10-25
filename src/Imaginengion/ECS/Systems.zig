//! The systems layer: runs systems across several ECSs. It sits on top of the ECSs and is optional, an ECS on its own
//! never needs it. It keeps a graph of the ECSs it knows (Register) and which of them know each other (Connect), and
//! RunSystem locks what a system lists across the ECS the run starts from and that ECS's connected neighbours, for as
//! long as the system runs (see ECSManager.Lock). See .claude/notes/systems-design.md.
//!
//! A system is a file:
//!
//!     pub const Name = "PhysicsStep";
//!     pub const Reads = &.{ ColliderComponent, EntitySceneComponent, Systems.In(SceneECS, ScenePhysicsComponent) };
//!     pub const Writes = &.{ RigidBodyComponent, TransformComponent };
//!     pub fn Run(engine_context: *EngineContext, world: *WorldManager) !void { ... }
//!
//! A plain type in .Reads or .Writes is locked in the ECS the run starts from. In(Kind, T) is locked in every ECS of
//! that kind connected to it. Run takes the context first, then whatever the call hands it, and returns what it likes.
const Systems = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
pub const RunInfo = @import("ECSManager.zig").RunInfo;

/// The most ECSs of one kind a run can reach through its In entries. Going past it is a wiring mistake, and stops
pub const MAX_PER_KIND = 8;

mNodes: std.ArrayList(Node) = .empty,
mEdges: std.ArrayList(Edge) = .empty,
/// The innermost run going on now. Every registered ECS points at this field for its debug checks, so the layer must
/// stay where it is while anything is registered
mCurrentRun: ?*const RunInfo = null,

pub const empty: Systems = .{};

/// One ECS the layer knows, by its address and its kind
const Node = struct {
    mECS: *anyopaque,
    mKind: u64,
};

/// Two ECSs that know each other
const Edge = struct {
    mA: Node,
    mB: Node,
};

/// An entry for .Reads or .Writes: the component `T` in the ECSs of kind `Kind` (an ECSManager type) connected to the
/// one the run starts from, however the system gets to it (following a link, a query)
pub fn In(comptime Kind: type, comptime T: type) type {
    return struct {
        pub const IsSystemsIn = {};
        pub const ECSKind = Kind;
        pub const Component = T;
    };
}

/// What tells kinds of ECS apart in the graph: a hash of the ECS type's name, the same in the engine and in a script
/// DLL's copy of this code (an address would differ)
pub fn KindId(comptime Kind: type) u64 {
    return comptime std.hash.Fnv1a_64.hash(Kind.DebugName);
}

pub fn Deinit(self: *Systems, engine_allocator: std.mem.Allocator) void {
    self.mNodes.deinit(engine_allocator);
    self.mEdges.deinit(engine_allocator);
}

//------------------------------the graph------------------------------

/// Makes `ecs` (a pointer to an ECSManager) known to the layer, so it can be connected to others, and checked by the
/// debug checks for being touched by a run it wasn't given to
pub fn Register(self: *Systems, engine_allocator: std.mem.Allocator, ecs: anytype) !void {
    const Kind = _ECSType(@TypeOf(ecs));
    std.debug.assert(self._FindNode(ecs) == null);
    try self.mNodes.append(engine_allocator, .{ .mECS = ecs, .mKind = KindId(Kind) });
    ecs.SetRunMarker(&self.mCurrentRun);
}

/// Forgets `ecs`, and every connection it has
pub fn Unregister(self: *Systems, ecs: anytype) void {
    _ = _ECSType(@TypeOf(ecs));
    const node_ind = self._FindNode(ecs) orelse return;
    ecs.SetRunMarker(null);
    var edge_ind = self.mEdges.items.len;
    while (edge_ind > 0) {
        edge_ind -= 1;
        const edge = self.mEdges.items[edge_ind];
        if (edge.mA.mECS == @as(*anyopaque, ecs) or edge.mB.mECS == @as(*anyopaque, ecs)) _ = self.mEdges.swapRemove(edge_ind);
    }
    _ = self.mNodes.swapRemove(node_ind);
}

/// Lets two registered ECSs know each other, so a run starting from either reaches the other through In. Connecting
/// two that already are does nothing
pub fn Connect(self: *Systems, engine_allocator: std.mem.Allocator, a: anytype, b: anytype) !void {
    _ = _ECSType(@TypeOf(a));
    _ = _ECSType(@TypeOf(b));
    std.debug.assert(@as(*anyopaque, a) != @as(*anyopaque, b));
    const node_a = self.mNodes.items[self._FindNode(a) orelse return error.ECSNotRegistered];
    const node_b = self.mNodes.items[self._FindNode(b) orelse return error.ECSNotRegistered];
    if (self._FindEdge(a, b) != null) return;
    try self.mEdges.append(engine_allocator, .{ .mA = node_a, .mB = node_b });
}

/// Undoes Connect. Two that aren't connected are left as they are
pub fn Disconnect(self: *Systems, a: anytype, b: anytype) void {
    _ = _ECSType(@TypeOf(a));
    _ = _ECSType(@TypeOf(b));
    const edge_ind = self._FindEdge(a, b) orelse return;
    _ = self.mEdges.swapRemove(edge_ind);
}

fn _FindNode(self: *const Systems, ecs: *anyopaque) ?usize {
    for (self.mNodes.items, 0..) |node, node_ind| {
        if (node.mECS == ecs) return node_ind;
    }
    return null;
}

fn _FindEdge(self: *const Systems, a: *anyopaque, b: *anyopaque) ?usize {
    for (self.mEdges.items, 0..) |edge, edge_ind| {
        if ((edge.mA.mECS == a and edge.mB.mECS == b) or (edge.mA.mECS == b and edge.mB.mECS == a)) return edge_ind;
    }
    return null;
}

// the ECSs of kind `Kind` connected to `start`, put in `out`; how many
fn _Neighbours(self: *const Systems, start: *anyopaque, comptime Kind: type, out: *[MAX_PER_KIND]*Kind) usize {
    const kind_id = KindId(Kind);
    var count: usize = 0;
    for (self.mEdges.items) |edge| {
        const other = if (edge.mA.mECS == start) edge.mB else if (edge.mB.mECS == start) edge.mA else continue;
        if (other.mKind != kind_id) continue;
        if (count == MAX_PER_KIND) std.debug.panic("more than {d} {s}s are connected to one ECS", .{ MAX_PER_KIND, Kind.DebugName });
        out[count] = @ptrCast(@alignCast(other.mECS));
        count += 1;
    }
    return count;
}

//------------------------------running systems------------------------------

/// Runs the system `S` starting from `start` (a pointer to an ECSManager): what it lists is locked in `start` and in
/// each connected ECS its In entries name, and each of those ECSs holds a record of what may be touched there (for the
/// debug checks), for as long as S.Run runs. S.Run gets `engine_context`, then `args` (a tuple) in order. What it
/// returns comes back, and so does its error; when it fails, what it changed still lands, and a failure landing it is
/// logged. A run inside another leaves the landing to the outer one wherever both locked.
/// error.NoConnectedECS, with nothing run, when an In kind has no ECS connected to `start`
pub fn RunSystem(self: *Systems, comptime S: type, engine_context: *EngineContext, start: anytype, args: anytype) anyerror!Payload(S) {
    const Start = _ECSType(@TypeOf(start));
    const plan = comptime _Plan(S, Start);
    comptime _CheckArgs(S, @TypeOf(args));

    const zone = Tracy.ZoneInit(S.Name, @src());
    defer zone.Deinit();

    var run: RunState(S, plan.kinds, plan.types) = undefined;
    try run.Find(self, start);
    var info: RunInfo = .{ .mName = S.Name, .mOuter = self.mCurrentRun };
    run.Enter(&info);
    self.mCurrentRun = &info;

    const result = @call(.auto, S.Run, .{engine_context} ++ args);

    //left before the unlock: what landing it sets off isn't the system's doing
    self.mCurrentRun = info.mOuter;
    const leave_err = run.Leave(engine_context);

    if (comptime _ReturnsError(S)) {
        const value = result catch |err| {
            if (leave_err) |landing_err| std.log.err("What " ++ S.Name ++ " changed could not all be made: {s}", .{@errorName(landing_err)});
            return err;
        };
        if (leave_err) |landing_err| return landing_err;
        return value;
    } else {
        if (leave_err) |landing_err| return landing_err;
        return result;
    }
}

/// What RunSystem hands back for `S` when nothing fails: what S.Run returns, without its error
pub fn Payload(comptime S: type) type {
    comptime _ValidateSystem(S);
    const R = @typeInfo(@TypeOf(S.Run)).@"fn".return_type.?;
    return switch (@typeInfo(R)) {
        .error_union => |error_union| error_union.payload,
        else => R,
    };
}

/// The window for engine work done inside a system that isn't the system's own (structural bookkeeping, the removal
/// hook): unchecked records on `start` and on each connected ECS of the kinds in `kinds`, so nothing touched in there
/// is charged to the system around it. Locks nothing. Lives on the caller's stack:
///
///     var unchecked: Systems.UncheckedScope(EntityECS, &.{ SceneECS, PlayerECS }) = undefined;
///     unchecked.Enter(systems, entity_ecs);
///     defer unchecked.Leave();
pub fn UncheckedScope(comptime Start: type, comptime kinds: []const type) type {
    const all_kinds: []const type = &([_]type{Start} ++ kinds[0..kinds.len].*);
    return struct {
        const Scope = @This();
        mSlots: Slots(all_kinds),

        pub fn Enter(scope: *Scope, systems: *const Systems, start: *Start) void {
            scope.mSlots[0].mECSs[0] = start;
            scope.mSlots[0].mCount = 1;
            inline for (all_kinds[1..], 1..) |Kind, kind_ind| {
                scope.mSlots[kind_ind].mCount = systems._Neighbours(start, Kind, &scope.mSlots[kind_ind].mECSs);
            }
            inline for (all_kinds, 0..) |Kind, kind_ind| {
                const slots = &scope.mSlots[kind_ind];
                for (slots.mECSs[0..slots.mCount], slots.mRecords[0..slots.mCount]) |ecs, *record| {
                    record.* = Kind.UncheckedRecord;
                    ecs.EnterSystem(record);
                }
            }
        }

        pub fn Leave(scope: *Scope) void {
            comptime var kind_ind: usize = all_kinds.len;
            inline while (kind_ind > 0) {
                kind_ind -= 1;
                const slots = &scope.mSlots[kind_ind];
                var ecs_ind = slots.mCount;
                while (ecs_ind > 0) {
                    ecs_ind -= 1;
                    slots.mECSs[ecs_ind].LeaveSystem(&slots.mRecords[ecs_ind]);
                }
            }
        }
    };
}

// one run's ECSs, records and the work of entering and leaving them: kind 0 is the ECS the run starts from, the rest
// its In kinds, each with the types locked there
fn RunState(comptime S: type, comptime kinds: []const type, comptime types: []const []const type) type {
    return struct {
        const State = @This();
        mSlots: Slots(kinds),

        fn Find(state: *State, systems: *const Systems, start: *kinds[0]) !void {
            state.mSlots[0].mECSs[0] = start;
            state.mSlots[0].mCount = 1;
            inline for (kinds[1..], 1..) |Kind, kind_ind| {
                const count = systems._Neighbours(start, Kind, &state.mSlots[kind_ind].mECSs);
                if (count == 0) {
                    //a warning, with the error handed back being the failure: says which kind the error is about
                    std.log.warn(S.Name ++ " lists components in a " ++ Kind.DebugName ++ ", but none is connected to the " ++ kinds[0].DebugName ++ " it was run from", .{});
                    return error.NoConnectedECS;
                }
                state.mSlots[kind_ind].mCount = count;
            }
        }

        fn Enter(state: *State, info: *const RunInfo) void {
            inline for (kinds, 0..) |Kind, kind_ind| {
                const record = comptime Kind.SystemRecordFor(S.Name, types[kind_ind]);
                const slots = &state.mSlots[kind_ind];
                for (slots.mECSs[0..slots.mCount], slots.mRecords[0..slots.mCount]) |ecs, *slot_record| {
                    ecs.Lock(types[kind_ind]);
                    slot_record.* = record;
                    slot_record.mRun = info;
                    ecs.EnterSystem(slot_record);
                }
            }
        }

        // the records go first, then every ECS is let go of even when one fails to land what waited, the first
        // failure handed back
        fn Leave(state: *State, engine_context: *EngineContext) ?anyerror {
            comptime var leave_ind: usize = kinds.len;
            inline while (leave_ind > 0) {
                leave_ind -= 1;
                const slots = &state.mSlots[leave_ind];
                var ecs_ind = slots.mCount;
                while (ecs_ind > 0) {
                    ecs_ind -= 1;
                    slots.mECSs[ecs_ind].LeaveSystem(&slots.mRecords[ecs_ind]);
                }
            }

            var first_err: ?anyerror = null;
            comptime var unlock_ind: usize = kinds.len;
            inline while (unlock_ind > 0) {
                unlock_ind -= 1;
                const slots = &state.mSlots[unlock_ind];
                var ecs_ind = slots.mCount;
                while (ecs_ind > 0) {
                    ecs_ind -= 1;
                    slots.mECSs[ecs_ind].Unlock(engine_context, types[unlock_ind]) catch |err| {
                        if (first_err == null) first_err = err;
                    };
                }
            }
            return first_err;
        }
    };
}

// for each kind, room for the ECSs of that kind a run reaches and a record on each
fn Slots(comptime kinds: []const type) type {
    var slot_types: [kinds.len]type = undefined;
    for (kinds, 0..) |Kind, kind_ind| {
        slot_types[kind_ind] = struct {
            mECSs: [MAX_PER_KIND]*Kind,
            mRecords: [MAX_PER_KIND]Kind.SystemRecord,
            mCount: usize,
        };
    }
    return @Tuple(&slot_types);
}

//------------------------------compile-time checks------------------------------

// the ECSManager type `P` points at, or a compile error
fn _ECSType(comptime P: type) type {
    const info = @typeInfo(P);
    if (info != .pointer or info.pointer.size != .one or @typeInfo(info.pointer.child) != .@"struct" or !@hasDecl(info.pointer.child, "DebugName")) {
        @compileError("the systems layer takes a pointer to an ECSManager, not a " ++ @typeName(P));
    }
    return info.pointer.child;
}

fn _ValidateSystem(comptime S: type) void {
    if (@typeInfo(S) != .@"struct") @compileError(@typeName(S) ++ " is not a system: a system is a file with Name, Reads, Writes and Run");
    inline for (.{ "Name", "Reads", "Writes", "Run" }) |decl_name| {
        if (!@hasDecl(S, decl_name)) @compileError(@typeName(S) ++ " is not a system: it has no pub " ++ decl_name ++ " (a system has Name, Reads, Writes and Run, &.{} for an empty list)");
    }
    const name: [:0]const u8 = S.Name;
    const run_info = switch (@typeInfo(@TypeOf(S.Run))) {
        .@"fn" => |fn_info| fn_info,
        else => @compileError(name ++ ": Run has to be a function"),
    };
    if (run_info.param_types.len == 0 or run_info.param_types[0] != *EngineContext) {
        @compileError(name ++ ": Run has to take the context first, Run(engine_context: *EngineContext, ...)");
    }
    if (run_info.return_type == null) @compileError(name ++ ": Run's return type has to be written out, not worked out from its arguments");
}

fn _ReturnsError(comptime S: type) bool {
    return @typeInfo(@typeInfo(@TypeOf(S.Run)).@"fn".return_type.?) == .error_union;
}

fn _CheckArgs(comptime S: type, comptime Args: type) void {
    const args_info = @typeInfo(Args);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError(S.Name ++ ": RunSystem takes Run's arguments as a tuple, .{ ... } (.{} for none)");
    }
    const param_count = @typeInfo(@TypeOf(S.Run)).@"fn".param_types.len - 1;
    const arg_count = args_info.@"struct".field_types.len;
    if (param_count != arg_count) {
        @compileError(std.fmt.comptimePrint("{s}.Run takes {d} argument(s) after the context, the call passed {d}", .{ S.Name, param_count, arg_count }));
    }
}

// which kinds of ECS a run of `S` from a `Start` reaches (Start first), and the types locked in each: Reads and Writes
// together, each type once
fn _Plan(comptime S: type, comptime Start: type) struct { kinds: []const type, types: []const []const type } {
    @setEvalBranchQuota(100_000);
    const entries = _Entries(S, "Reads", S.Reads) ++ _Entries(S, "Writes", S.Writes);

    var kinds: []const type = &.{Start};
    for (entries) |entry| {
        if (!_IsIn(entry)) {
            if (!Start.HasType(entry)) {
                @compileError(S.Name ++ " lists " ++ @typeName(entry) ++ ", which a " ++ Start.DebugName ++ " (what it was run from) doesn't have. One in another ECS is Systems.In(ThatECS, " ++ @typeName(entry) ++ ")");
            }
            continue;
        }
        const Kind = entry.ECSKind;
        if (@typeInfo(Kind) != .@"struct" or !@hasDecl(Kind, "DebugName")) @compileError(S.Name ++ ": In takes an ECSManager type first, not " ++ @typeName(Kind));
        if (Kind == Start) {
            @compileError(S.Name ++ " lists In(" ++ Kind.DebugName ++ ", " ++ @typeName(entry.Component) ++ ") but runs from a " ++ Kind.DebugName ++ ": list " ++ @typeName(entry.Component) ++ " plainly");
        }
        if (!Kind.HasType(entry.Component)) @compileError(S.Name ++ " lists In(" ++ Kind.DebugName ++ ", " ++ @typeName(entry.Component) ++ "), but a " ++ Kind.DebugName ++ " has no " ++ @typeName(entry.Component));
        if (!_Contains(kinds, Kind)) kinds = kinds ++ [_]type{Kind};
    }

    var types: []const []const type = &.{};
    for (kinds) |Kind| {
        var kind_types: []const type = &.{};
        for (entries) |entry| {
            const listed, const listed_kind = if (_IsIn(entry)) .{ entry.Component, entry.ECSKind } else .{ entry, Start };
            if (listed_kind != Kind or _Contains(kind_types, listed)) continue;
            kind_types = kind_types ++ [_]type{listed};
        }
        types = types ++ [_][]const type{kind_types};
    }
    return .{ .kinds = kinds, .types = types };
}

// the entries of one of the system's lists, as a slice: written as &.{ A, B }, .{ A, B } or a []const type. A type
// listed twice in the same list is a mistake
fn _Entries(comptime S: type, comptime list_name: []const u8, comptime list: anytype) []const type {
    comptime var entries: []const type = &.{};
    const L = @TypeOf(list);
    switch (@typeInfo(L)) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => for (list) |listed| {
                entries = entries ++ [_]type{listed};
            },
            .one => inline for (list.*) |listed| {
                entries = entries ++ [_]type{_ListedType(S, list_name, listed)};
            },
            else => @compileError(S.Name ++ ": " ++ list_name ++ " has to be a list of components, &.{ ... }"),
        },
        .@"struct", .array => inline for (list) |listed| {
            entries = entries ++ [_]type{_ListedType(S, list_name, listed)};
        },
        else => @compileError(S.Name ++ ": " ++ list_name ++ " has to be a list of components, &.{ ... }"),
    }
    for (entries, 0..) |listed, listed_ind| {
        for (entries[listed_ind + 1 ..]) |other| {
            if (listed == other) @compileError(S.Name ++ " lists " ++ @typeName(listed) ++ " twice in " ++ list_name);
        }
    }
    return entries;
}

fn _ListedType(comptime S: type, comptime list_name: []const u8, comptime listed: anytype) type {
    if (@TypeOf(listed) != type) @compileError(S.Name ++ ": " ++ list_name ++ " has something that isn't a component type in it");
    return listed;
}

fn _IsIn(comptime entry: type) bool {
    return @typeInfo(entry) == .@"struct" and @hasDecl(entry, "IsSystemsIn");
}

fn _Contains(comptime types: []const type, comptime wanted: type) bool {
    for (types) |listed| {
        if (listed == wanted) return true;
    }
    return false;
}
