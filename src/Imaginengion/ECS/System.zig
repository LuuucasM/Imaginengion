//! A system: one function, and what it touches, described once next to the function. Running it (ECSManager.RunSystem,
//! or something built on it for several ECSs) locks what it touches for as long as it runs (see ECSManager.Lock), so
//! adds, removals and destroys of those components wait until it is done, while changes to anything else are made
//! right away. That is what lets a system hold pointers, slices or lists of ids into what it touches while the code it
//! calls into changes things.
//!
//!     pub const StepSystem = System(.{
//!         .Name = "PhysicsStep",
//!         .Reads = &.{ ColliderComponent },
//!         .Writes = &.{ RigidBodyComponent, TransformComponent },
//!         .Run = Step,
//!     });
//!
//! .Name is what profiling and errors call it. .Reads lists the components it holds onto or reads, .Writes the ones it
//! changes the values of; both are locked the same way for now, the difference is for scheduling. Either can be left
//! out. .Run can take any parameters, each one supplied by type by whatever runs the system (see Call).
//!
//! The function is the system, not the struct it lives on: something with several functions has several systems, or
//! some of them are plain helpers that run inside a system and are covered by what that system lists.
const std = @import("std");

/// The type a description (see the top of the file) stands for: Name, Reads, Writes, Run, and Accessed, which is what
/// running it locks
pub fn System(comptime description: anytype) type {
    const D = @TypeOf(description);
    if (@typeInfo(D) != .@"struct") @compileError("System takes a description: .{ .Name, .Reads, .Writes, .Run }");

    for (@typeInfo(D).@"struct".field_names) |field_name| {
        const known = std.mem.eql(u8, field_name, "Name") or std.mem.eql(u8, field_name, "Reads") or
            std.mem.eql(u8, field_name, "Writes") or std.mem.eql(u8, field_name, "Run");
        if (!known) @compileError("System: unknown field ." ++ field_name ++ ", it takes .Name, .Reads, .Writes and .Run");
    }
    if (!@hasField(D, "Name")) @compileError("System: a system needs a .Name");
    const name: [:0]const u8 = description.Name;
    if (!@hasField(D, "Run")) @compileError("System " ++ name ++ " needs a .Run");

    const reads = TypeList(name, "Reads", if (@hasField(D, "Reads")) description.Reads else .{});
    const writes = TypeList(name, "Writes", if (@hasField(D, "Writes")) description.Writes else .{});
    _ValidateRun(name, description.Run);

    return struct {
        pub const Name: [:0]const u8 = name;
        pub const Reads: []const type = reads;
        pub const Writes: []const type = writes;
        pub const Run = description.Run;
        /// Reads and Writes together, each type once
        pub const Accessed: []const type = _Union(reads, writes);
        /// What tells a system from any other type, for what runs one
        pub const IsSystem = {};
    };
}

/// What something that touches components the way a system does locks: its reads and writes (each a list of component
/// types, written the way a system's are) checked and put together, each type once. For what isn't made with System
/// but locks like one, a script for instance; `name` is for its compile errors
pub fn Access(comptime name: []const u8, comptime reads: anytype, comptime writes: anytype) []const type {
    return _Union(TypeList(name, "Reads", reads), TypeList(name, "Writes", writes));
}

/// Runs `S.Run` with each of its parameters asked of `provider`, by type: `provider.Get(ParamType)`. Whatever runs a
/// system decides what it can supply; a parameter it can't is a compile error there
pub fn Call(comptime S: type, provider: anytype) anyerror!void {
    const param_types = @typeInfo(@TypeOf(S.Run)).@"fn".param_types;
    var args: std.meta.ArgsTuple(@TypeOf(S.Run)) = undefined;
    inline for (param_types, 0..) |param_type, param_ind| {
        args[param_ind] = provider.Get(param_type.?);
    }
    return @call(.auto, S.Run, args);
}

/// A compile error unless `S` was made by System
pub fn Validate(comptime S: type) void {
    if (!@hasDecl(S, "IsSystem")) @compileError(@typeName(S) ++ " is not a system: make it with System(.{ ... })");
}

// the types in .Reads or .Writes, as a slice: written as &.{ A, B }, .{ A, B }, or a []const type of their own
fn TypeList(comptime system_name: []const u8, comptime field_name: []const u8, comptime list: anytype) []const type {
    comptime var types: []const type = &.{};
    const L = @TypeOf(list);
    switch (@typeInfo(L)) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => for (list) |listed| {
                types = types ++ [_]type{listed};
            },
            .one => inline for (list.*) |listed| {
                types = types ++ [_]type{_ListedType(system_name, field_name, listed)};
            },
            else => @compileError("System " ++ system_name ++ ": ." ++ field_name ++ " has to be a list of components"),
        },
        .@"struct", .array => inline for (list) |listed| {
            types = types ++ [_]type{_ListedType(system_name, field_name, listed)};
        },
        else => @compileError("System " ++ system_name ++ ": ." ++ field_name ++ " has to be a list of components"),
    }

    for (types, 0..) |listed, listed_ind| {
        for (types[listed_ind + 1 ..]) |other| {
            if (listed == other) @compileError("System " ++ system_name ++ " lists " ++ @typeName(listed) ++ " twice in ." ++ field_name);
        }
    }
    return types;
}

fn _ListedType(comptime system_name: []const u8, comptime field_name: []const u8, comptime listed: anytype) type {
    if (@TypeOf(listed) != type) @compileError("System " ++ system_name ++ ": ." ++ field_name ++ " has something that isn't a component type in it");
    return listed;
}

fn _ValidateRun(comptime system_name: []const u8, comptime run: anytype) void {
    const run_info = @typeInfo(@TypeOf(run));
    if (run_info != .@"fn") @compileError("System " ++ system_name ++ ": .Run has to be a function");
    for (run_info.@"fn".param_types) |param_type| {
        if (param_type == null) @compileError("System " ++ system_name ++ ": .Run's parameters need types of their own, for whatever runs it to supply them by");
    }
    const return_type = run_info.@"fn".return_type orelse @compileError("System " ++ system_name ++ ": .Run needs a return type of its own");
    const returns_void = return_type == void or
        (@typeInfo(return_type) == .error_union and @typeInfo(return_type).error_union.payload == void);
    if (!returns_void) @compileError("System " ++ system_name ++ ": .Run has to return void, or an error union of void");
}

// `first`, then whatever of `second` isn't in it already
fn _Union(comptime first: []const type, comptime second: []const type) []const type {
    comptime var types: []const type = first;
    for (second) |listed| {
        for (first) |other| {
            if (listed == other) break;
        } else types = types ++ [_]type{listed};
    }
    return types;
}
