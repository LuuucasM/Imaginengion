//! The systems layer: runs the engine's passes. It sits on top of the ECSs and is optional, an ECS on its own never
//! needs it. While any run is going on, every ECS it knows (Register) holds its structural changes, so nothing a running
//! system holds can move, and they land when the last run ends (see ECSManager.mRunDepth).
//!
//! A system is a file, or a struct nested in the file of what it works on:
//!
//!     pub const Name = "PhysicsStep";
//!     pub fn Run(engine_context: *EngineContext, world: *WorldManager) !void { ... }
//!
//! Run takes the context first, then whatever the call hands it, and returns what it likes.
const Systems = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const Transaction = @import("Transaction.zig");

mNodes: std.ArrayList(Node) = .empty,
/// How many runs are going on now. Every registered ECS points at this, so the layer must stay where it is while anything
/// is registered
mRunDepth: u32 = 0,
/// The last run has ended and what the ECSs held is landing. What that sets off can run a system, which leaves its own
/// changes to this same landing
mLanding: bool = false,
/// The one transaction there is (RunTransaction), kept between uses for its memory
mTransaction: Transaction = .empty,
/// mTransaction while it is open, null otherwise. Every registered ECS points at this, see ECSManager.mTransaction
mOpenTransaction: ?*Transaction = null,

pub const empty: Systems = .{};

/// One ECS the layer knows
const Node = struct {
    mECS: *anyopaque,
    /// ECSManager.LandQueued for this ECS. A pointer into the engine's own code, so a script DLL's copy of this layer
    /// lands through the same code as the engine
    mLand: *const fn (ecs: *anyopaque, engine_context: *EngineContext) anyerror!bool,
};

pub fn Deinit(self: *Systems, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self.mOpenTransaction == null);
    self.mNodes.deinit(engine_allocator);
    self.mNodes = .empty;
    self.mTransaction.Deinit(engine_allocator);
}

/// Makes `ecs` (a pointer to an ECSManager) hold its changes while a run goes on
pub fn Register(self: *Systems, engine_allocator: std.mem.Allocator, ecs: anytype) !void {
    const Kind = @typeInfo(@TypeOf(ecs)).pointer.child;
    std.debug.assert(!self.IsRegistered(ecs));
    try self.mNodes.append(engine_allocator, .{ .mECS = ecs, .mLand = struct {
        fn Land(erased: *anyopaque, engine_context: *EngineContext) anyerror!bool {
            const typed: *Kind = @ptrCast(@alignCast(erased));
            return typed.LandQueued(engine_context);
        }
    }.Land });
    ecs.SetRunDepth(&self.mRunDepth);
    ecs.SetTransaction(&self.mOpenTransaction);
}

/// Forgets `ecs`. Once the last one is gone the layer lets go of its memory too, so what registers in its Init and
/// unregisters in its Deinit leaves nothing behind
pub fn Unregister(self: *Systems, engine_allocator: std.mem.Allocator, ecs: anytype) void {
    for (self.mNodes.items, 0..) |node, node_ind| {
        if (node.mECS != @as(*anyopaque, ecs)) continue;
        ecs.SetRunDepth(null);
        ecs.SetTransaction(null);
        _ = self.mNodes.swapRemove(node_ind);
        if (self.mNodes.items.len == 0) self.Deinit(engine_allocator);
        return;
    }
}

/// Whether `ecs` is registered
pub fn IsRegistered(self: *const Systems, ecs: *anyopaque) bool {
    for (self.mNodes.items) |node| {
        if (node.mECS == ecs) return true;
    }
    return false;
}

/// Runs the system `S`: S.Run gets `engine_context`, then `args` (a tuple) in order. What it returns comes back, and so
/// does its error; when it fails, what it changed still lands, and a failure landing it is logged. A run inside another
/// leaves the landing to the outermost one
pub fn RunSystem(self: *Systems, comptime S: type, engine_context: *EngineContext, args: anytype) anyerror!Payload(S) {
    comptime _CheckArgs(S, @TypeOf(args));

    const zone = Tracy.ZoneInit(S.Name, @src());
    defer zone.Deinit();

    self.mRunDepth += 1;
    const result = @call(.auto, S.Run, .{engine_context} ++ args);
    self.mRunDepth -= 1;
    const landing_err = if (self.mRunDepth == 0) self._Land(engine_context) else null;

    if (comptime _ReturnsError(S)) {
        const value = result catch |err| {
            if (landing_err) |land_err| std.log.err("What " ++ S.Name ++ " changed could not all be made: {s}", .{@errorName(land_err)});
            return err;
        };
        if (landing_err) |land_err| return land_err;
        return value;
    } else {
        if (landing_err) |land_err| return land_err;
        return result;
    }
}

/// Calls `func` with `args` (a tuple) inside a transaction, and hands back what it returns. What it changes in a
/// registered ECS is kept apart or written down until it returns (see Transaction): component values, adds, removals,
/// destroys, objects made and tags. Then it is kept when `keep(result)` says so, and dropped otherwise, as if it never
/// happened: the script runner keeps a hook's changes unless the hook failed.
/// A transaction is also a run, so structural changes wait in it the same way, and land after it when it is the
/// outermost run (a failure landing them is logged). Inside a transaction already, `func` is part of that one, and what
/// it changed goes or stays with it.
pub fn RunTransaction(self: *Systems, engine_context: *EngineContext, comptime func: anytype, args: anytype, comptime keep: anytype) ReturnOf(func) {
    if (self.mOpenTransaction != null) return @call(.auto, func, args);

    self.mRunDepth += 1;
    self.mTransaction.Open(engine_context);
    self.mOpenTransaction = &self.mTransaction;
    const result = @call(.auto, func, args);
    self.mOpenTransaction = null;

    // still inside the run: what keeping or dropping sets off waits like anything else in it. One that did something
    // that can't be taken back is kept whatever happened, rather than coming out half undone
    if (keep(result)) {
        self.mTransaction.Commit(engine_context);
    } else if (self.mTransaction.mIrrevocable) |reason| {
        std.log.warn("A failed transaction was kept, since it did something that can't be taken back: {s}", .{reason});
        self.mTransaction.Commit(engine_context);
    } else {
        self.mTransaction.Discard(engine_context);
    }

    self.mRunDepth -= 1;
    if (self.mRunDepth == 0) {
        if (self._Land(engine_context)) |err| std.log.err("What a transaction changed could not all be made: {s}", .{@errorName(err)});
    }
    return result;
}

/// The transaction open now, null outside one: for code outside the ECSs to hold its changes back in
/// (Transaction.OnCommit, OnDiscard)
pub fn OpenTransaction(self: *const Systems) ?*Transaction {
    return self.mOpenTransaction;
}

/// Says that what the caller is about to do can't be taken back, so an open transaction is kept even if its code fails
/// (Transaction.MarkIrrevocable). Nothing outside a transaction
pub fn MarkIrrevocable(self: *const Systems, reason: []const u8) void {
    if (self.mOpenTransaction) |transaction| transaction.MarkIrrevocable(reason);
}

/// What `func` returns
pub fn ReturnOf(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

// the last run has ended: every ECS makes the changes it held. What that sets off can queue more in an ECS already
// passed, so it goes round until none has any. One that fails to land isn't asked again this time. The first failure
// is handed back
fn _Land(self: *Systems, engine_context: *EngineContext) ?anyerror {
    if (self.mLanding) return null;
    self.mLanding = true;
    defer self.mLanding = false;

    var first_err: ?anyerror = null;
    var landed = true;
    while (landed) {
        landed = false;
        for (self.mNodes.items) |node| {
            const any = node.mLand(node.mECS, engine_context) catch |err| {
                if (first_err == null) first_err = err;
                continue;
            };
            if (any) landed = true;
        }
    }
    return first_err;
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

fn _ValidateSystem(comptime S: type) void {
    if (@typeInfo(S) != .@"struct") @compileError(@typeName(S) ++ " is not a system: a system is a file with Name and Run");
    inline for (.{ "Name", "Run" }) |decl_name| {
        if (!@hasDecl(S, decl_name)) @compileError(@typeName(S) ++ " is not a system: it has no pub " ++ decl_name);
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
