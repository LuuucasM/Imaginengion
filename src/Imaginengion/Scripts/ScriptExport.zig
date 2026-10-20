//! The half of a script's DLL nobody writes. `zig build script` builds a script around a small generated root that
//! exports `&Exports(Script, name).info` (see build_script.zig), and everything the engine needs comes from looking at
//! the script's struct at compile time:
//! - its variables, as a table of names, kinds and offsets (FieldDesc) the engine edits, saves and copies them with
//! - its hooks: any of ScriptABI.Hook it has a function for, each wrapped in a C-callable function that finds the
//!   variables for the instance it is run on
//! - its game event handlers: any function whose last parameter is a game event (see GameEvents), whatever it is
//!   called, each wrapped the same way and listed by the event's id
//! - where the instances are kept: one sparse set per DLL, by the instance id the engine hands it, each instance in an
//!   allocation of its own so it stays put
//! - the project files it imports, which build_script.zig found and hands in, for the engine to watch
//! - what it touches, its Reads and Writes, which every hook and handler of it runs locked by (see AccessOf)
//! A script that doesn't fit (a variable with no default, a hook with the wrong parameters) is a compile error saying
//! what to change.
const std = @import("std");
const ScriptABI = @import("ScriptABI.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const SparseSet = @import("../Core/SparseSet.zig").SparseSet;
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const GameEvents = @import("GameEvents.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const System = @import("../ECS/System.zig");

const Hook = ScriptABI.Hook;
const OwnerKind = ScriptABI.OwnerKind;
const FieldKind = ScriptABI.FieldKind;
const FieldDesc = ScriptABI.FieldDesc;
const ScriptInfo = ScriptABI.ScriptInfo;
const ScriptResult = ScriptABI.ScriptResult;

/// Everything the DLL of `Script` (a script file's struct) exports. `script_name` is only for messages. `dependencies`
/// are the absolute paths of the project files it imports
pub fn Exports(comptime Script: type, comptime script_name: []const u8, comptime dependencies: []const [*:0]const u8) type {
    const owner_kind = comptime OwnerOf(Script, script_name);
    const Owner = owner_kind.Type();
    const fields = comptime FieldsOf(Script, script_name);
    const handler_names = comptime HandlerNames(Script, script_name);
    const accessed = comptime AccessOf(Script, script_name);
    const scope_name = std.fmt.comptimePrint("{s}", .{script_name});

    return struct {
        /// the instances, by the ids the engine hands out (u20 for the index, as the ECS does). Each is allocated on its
        /// own so it never moves: a hook can make another instance (spawn a copy of its object) while its self is in use
        var gInstances: SparseSet(u32, u20, *Script, false) = .empty;

        pub const info: ScriptInfo = .{
            .mOwner = owner_kind,
            .mHooks = Hooks(),
            .mFields = &fields,
            .mFieldCount = fields.len,
            .mDataSize = @sizeOf(Script),
            .mNewInstance = &NewInstance,
            .mFreeInstance = &FreeInstance,
            .mGetInstance = &GetInstance,
            .mDeinit = &Deinit,
            .mHandlers = &handlers,
            .mHandlerCount = handlers.len,
            .mDependencies = dependencies.ptr,
            .mDependencyCount = dependencies.len,
        };

        const handlers = Handlers();

        fn Handlers() [handler_names.len]ScriptABI.EventHandler {
            @setEvalBranchQuota(100_000);
            var table: [handler_names.len]ScriptABI.EventHandler = undefined;
            for (handler_names, 0..) |name, i| {
                const Event = EventOf(Script, @TypeOf(@field(Script, name))).?;
                table[i] = .{
                    .mId = GameEvents.IdOf(Event),
                    .mName = GameEvents.NameOf(Event).ptr,
                    .mFn = @ptrCast(HandlerWrapper(name, Event)),
                };
            }
            return table;
        }

        /// The C-callable function for the handler `name` of `Event`: the event's bytes back into an Event
        fn HandlerWrapper(comptime name: []const u8, comptime Event: type) ScriptABI.HandlerFn(Owner) {
            return &struct {
                fn Run(ec: *EngineContext, owner: *const Owner, data: *anyopaque, event: *const anyopaque) callconv(.c) ScriptResult {
                    const self: *Script = @ptrCast(@alignCast(data));
                    var scope: Scope = .{};
                    scope.Enter(owner.mManager);
                    defer LeaveScope(&scope, owner.mManager, ec, name);
                    return Finish(name, @field(Script, name)(self, ec, owner.*, @as(*const Event, @ptrCast(@alignCast(event)))));
                }
            }.Run;
        }

        fn NewInstance(engine_context: *EngineContext, id: u32, copy_from: ?*const anyopaque) callconv(.c) bool {
            const engine_allocator = engine_context.EngineAllocator();
            const instance = engine_allocator.create(Script) catch return false;
            instance.* = if (copy_from) |from| @as(*const Script, @ptrCast(@alignCast(from))).* else .{};
            _ = gInstances.AddValue(engine_allocator, id, instance) catch {
                engine_allocator.destroy(instance);
                return false;
            };
            return true;
        }

        fn FreeInstance(engine_context: *EngineContext, id: u32) callconv(.c) void {
            if (!gInstances.HasSparse(id)) return;
            engine_context.EngineAllocator().destroy(gInstances.GetValueBySparse(id).*);
            gInstances.Remove(id);
        }

        fn GetInstance(id: u32) callconv(.c) ?*anyopaque {
            if (!gInstances.HasSparse(id)) return null;
            return @ptrCast(gInstances.GetValueBySparse(id).*);
        }

        fn Deinit(engine_context: *EngineContext) callconv(.c) void {
            const engine_allocator = engine_context.EngineAllocator();
            for (gInstances.mValues.items) |instance| engine_allocator.destroy(instance);
            gInstances.Deinit(engine_allocator);
            gInstances = .empty;
        }

        fn Hooks() [ScriptABI.HOOK_COUNT]?*const anyopaque {
            @setEvalBranchQuota(100_000);
            var hooks: [ScriptABI.HOOK_COUNT]?*const anyopaque = @splat(null);
            for (std.enums.values(Hook)) |hook| {
                if (@hasDecl(Script, @tagName(hook))) hooks[@intFromEnum(hook)] = @ptrCast(Wrapper(hook));
            }
            return hooks;
        }

        /// The C-callable function for `hook`, with the parameters ScriptABI.HookFn gives it
        fn Wrapper(comptime hook: Hook) ScriptABI.HookFn(Owner, hook) {
            const P = AbiParams(hook);
            return switch (P.len) {
                0 => &struct {
                    fn Run(ec: *EngineContext, owner: *const Owner, data: *anyopaque) callconv(.c) ScriptResult {
                        return Call(hook, ec, owner, data, .{});
                    }
                }.Run,
                1 => &struct {
                    fn Run(ec: *EngineContext, owner: *const Owner, data: *anyopaque, a: P[0]) callconv(.c) ScriptResult {
                        return Call(hook, ec, owner, data, .{FromAbi(a)});
                    }
                }.Run,
                2 => &struct {
                    fn Run(ec: *EngineContext, owner: *const Owner, data: *anyopaque, a: P[0], b: P[1]) callconv(.c) ScriptResult {
                        return Call(hook, ec, owner, data, .{ FromAbi(a), FromAbi(b) });
                    }
                }.Run,
                else => @compileError("no wrapper for a hook with this many parameters"),
            };
        }

        fn AbiParams(comptime hook: Hook) []const type {
            const fn_info = @typeInfo(@typeInfo(ScriptABI.HookFn(Owner, hook)).pointer.child).@"fn";
            var types: [fn_info.param_types.len - 3]type = undefined;
            for (fn_info.param_types[3..], 0..) |param, i| types[i] = param.?;
            const final = types;
            return &final;
        }

        fn Call(comptime hook: Hook, engine_context: *EngineContext, owner: *const Owner, data: *anyopaque, args: anytype) ScriptResult {
            const self: *Script = @ptrCast(@alignCast(data));
            var scope: Scope = .{};
            scope.Enter(owner.mManager);
            defer LeaveScope(&scope, owner.mManager, engine_context, @tagName(hook));
            return Finish(@tagName(hook), @call(.auto, @field(Script, @tagName(hook)), .{ self, engine_context, owner.* } ++ args));
        }

        /// The window each hook and handler runs in on its owner's world: what the script lists locked, and checked
        const Scope = WorldManager.SystemScope(scope_name, accessed);

        fn LeaveScope(scope: *Scope, world: *WorldManager, engine_context: *EngineContext, comptime function_name: []const u8) void {
            scope.Leave(world, engine_context) catch |err| {
                std.log.err("{s}.{s}: what it changed could not all be made: {s}", .{ script_name, function_name, @errorName(err) });
            };
        }

        /// What a hook or handler handed back, an error logged with the script's name and handed back as .Error
        fn Finish(comptime function_name: []const u8, result: anytype) ScriptResult {
            if (@typeInfo(@TypeOf(result)) == .error_union) {
                return result catch |err| {
                    std.log.err("{s}.{s}: {s}", .{ script_name, function_name, @errorName(err) });
                    return .Error;
                };
            }
            return result;
        }
    };
}

/// What the script touches: its `pub const Reads` and `pub const Writes`, both required (`&.{}` for none), checked the
/// way a system's are (ECS/System.zig). While any of its hooks or handlers runs, these are locked on its owner's world,
/// so adding or removing them waits until it is done, and a Debug build stops on anything else it gets a pointer into
fn AccessOf(comptime Script: type, comptime script_name: []const u8) []const type {
    if (!@hasDecl(Script, "Reads") or !@hasDecl(Script, "Writes")) {
        @compileError(script_name ++ ": a script lists the components it touches, pub const Reads = &.{ ... }; and pub const Writes = &.{ ... }; (&.{} for none). They are locked while it runs, and a Debug build stops on anything it touches but didn't list");
    }
    return System.Access(script_name, Script.Reads, Script.Writes);
}

/// An object handle comes over the DLL boundary by pointer, the hook gets it as a value
fn FromAbi(value: anytype) if (@TypeOf(value) == *const Entity) Entity else @TypeOf(value) {
    return if (@TypeOf(value) == *const Entity) value.* else value;
}

/// The object type the script goes on, from its hooks' and event handlers' third parameter: every one has to agree, and
/// each hook has to be one that object type has
fn OwnerOf(comptime Script: type, comptime script_name: []const u8) OwnerKind {
    //looking over every declaration and hook takes more compile-time steps than Zig allows by default
    @setEvalBranchQuota(100_000);
    if (@typeInfo(Script) != .@"struct") @compileError(script_name ++ ": a script is a struct file: its variables at the top, then its hooks");
    CheckNoMisspeltHooks(Script, script_name);

    var owner: ?OwnerKind = null;
    var first_hook: []const u8 = "";
    for (std.enums.values(Hook)) |hook| {
        if (!@hasDecl(Script, @tagName(hook))) continue;
        const func = @field(Script, @tagName(hook));
        const fn_info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |fn_info| fn_info,
            else => @compileError(script_name ++ ": " ++ @tagName(hook) ++ " has to be a function"),
        };
        if (fn_info.param_types.len < 3 or fn_info.param_types[2] == null) {
            @compileError(script_name ++ ": " ++ @tagName(hook) ++ " has to start (self: *@This(), engine_context: *EngineContext, owner: <Entity, SceneLayer, Player or GameContext>, ...)");
        }
        const this_owner = OwnerKind.Of(fn_info.param_types[2].?);
        if (owner) |kind| {
            if (kind != this_owner) @compileError(script_name ++ ": " ++ first_hook ++ "'s owner is " ++ @tagName(kind) ++ " but " ++ @tagName(hook) ++ "'s is " ++ @tagName(this_owner) ++ ": a script goes on one kind of object");
        } else {
            owner = this_owner;
            first_hook = @tagName(hook);
        }
        if (!hook.Takes(this_owner)) @compileError(script_name ++ ": a script whose owner is " ++ @tagName(this_owner) ++ " can't have " ++ @tagName(hook));
        CheckSignature(Script, script_name, hook, this_owner.Type(), fn_info);
    }
    for (HandlerNames(Script, script_name)) |name| {
        const fn_info = @typeInfo(@TypeOf(@field(Script, name))).@"fn";
        if (fn_info.param_types.len != 4 or fn_info.param_types[2] == null) {
            @compileError(script_name ++ ": " ++ name ++ " handles a game event, so it has to be (self: *@This(), engine_context: *EngineContext, owner: <Entity, SceneLayer, Player or GameContext>, event: *const <the event>) ScriptResult (or !ScriptResult)");
        }
        const this_owner = OwnerKind.Of(fn_info.param_types[2].?);
        if (owner) |kind| {
            if (kind != this_owner) @compileError(script_name ++ ": " ++ first_hook ++ "'s owner is " ++ @tagName(kind) ++ " but " ++ name ++ "'s is " ++ @tagName(this_owner) ++ ": a script goes on one kind of object");
        } else {
            owner = this_owner;
            first_hook = name;
        }
        CheckHandlerSignature(Script, script_name, name, this_owner.Type(), fn_info);
    }
    return owner orelse @compileError(script_name ++ ": has none of the hook functions or game event handlers, so nothing would ever run it. Add one, e.g. pub fn OnUpdate(self: *@This(), engine_context: *EngineContext, owner: Entity) !ScriptResult");
}

/// The game event a function of the script handles: the event its last parameter points at, null for a function that
/// isn't a handler. Only one taking the script's self first, so a helper that is handed an event isn't taken for one
fn EventOf(comptime Script: type, comptime F: type) ?type {
    const fn_info = switch (@typeInfo(F)) {
        .@"fn" => |fn_info| fn_info,
        else => return null,
    };
    if (fn_info.param_types.len < 2 or fn_info.param_types[0] != *Script) return null;
    const last = fn_info.param_types[fn_info.param_types.len - 1] orelse return null;
    const pointer = switch (@typeInfo(last)) {
        .pointer => |pointer| pointer,
        else => return null,
    };
    if (pointer.size != .one or !GameEvents.IsEvent(pointer.child)) return null;
    return pointer.child;
}

/// The names of the script's game event handlers, in the order it declares them. Two for one event is an error
fn HandlerNames(comptime Script: type, comptime script_name: []const u8) []const []const u8 {
    //looking over every declaration and hook takes more compile-time steps than Zig allows by default
    @setEvalBranchQuota(100_000);
    comptime var names: []const []const u8 = &.{};
    for (@typeInfo(Script).@"struct".decl_names) |name| {
        const Event = EventOf(Script, @TypeOf(@field(Script, name))) orelse continue;
        GameEvents.Check(Event);
        for (names) |other| {
            if (EventOf(Script, @TypeOf(@field(Script, other))).? == Event) {
                @compileError(script_name ++ ": " ++ other ++ " and " ++ name ++ " both handle " ++ GameEvents.NameOf(Event) ++ ": a script handles an event with one function");
            }
        }
        names = names ++ [_][]const u8{name};
    }
    return names;
}

fn CheckHandlerSignature(comptime Script: type, comptime script_name: []const u8, comptime name: []const u8, comptime Owner: type, comptime fn_info: std.builtin.Type.Fn) void {
    const Event = EventOf(Script, @TypeOf(@field(Script, name))).?;
    const message = script_name ++ ": " ++ name ++ " handles " ++ GameEvents.NameOf(Event) ++ ", so it has to be (self: *@This(), engine_context: *EngineContext, owner: " ++
        @typeName(Owner) ++ ", event: *const " ++ GameEvents.NameOf(Event) ++ ") ScriptResult (or !ScriptResult)";
    const expected = [_]type{ *Script, *EngineContext, Owner, *const Event };
    for (fn_info.param_types, expected) |param, want| {
        if (param != want) @compileError(message);
    }
    const return_type = fn_info.return_type orelse @compileError(message);
    const result = switch (@typeInfo(return_type)) {
        .error_union => |error_union| error_union.payload,
        else => return_type,
    };
    if (result != ScriptResult) @compileError(message);
}

fn CheckSignature(comptime Script: type, comptime script_name: []const u8, comptime hook: Hook, comptime Owner: type, comptime fn_info: std.builtin.Type.Fn) void {
    const expected = [_]type{ *Script, *EngineContext, Owner } ++ hook.Params()[0..hook.Params().len].*;
    comptime var wanted: []const u8 = "(self: *@This(), engine_context: *EngineContext, owner: " ++ @typeName(Owner);
    inline for (hook.Params()) |param| wanted = wanted ++ ", " ++ @typeName(param);
    wanted = wanted ++ ") ScriptResult (or !ScriptResult)";

    const message = script_name ++ ": " ++ @tagName(hook) ++ " has to be " ++ wanted;
    if (fn_info.param_types.len != expected.len) @compileError(message);
    for (fn_info.param_types, expected) |param, want| {
        if (param != want) @compileError(message);
    }
    const return_type = fn_info.return_type orelse @compileError(message);
    const result = switch (@typeInfo(return_type)) {
        .error_union => |error_union| error_union.payload,
        else => return_type,
    };
    if (result != ScriptResult) @compileError(message);
}

/// A public function named like a hook that isn't one (OnUpate) would never run, so it is an error
fn CheckNoMisspeltHooks(comptime Script: type, comptime script_name: []const u8) void {
    //looking over every declaration and hook takes more compile-time steps than Zig allows by default
    @setEvalBranchQuota(100_000);
    for (@typeInfo(Script).@"struct".decl_names) |name| {
        if (name.len < 3 or !std.mem.startsWith(u8, name, "On") or !std.ascii.isUpper(name[2])) continue;
        if (@typeInfo(@TypeOf(@field(Script, name))) != .@"fn") continue;
        if (std.meta.stringToEnum(Hook, name) != null) continue;
        //a game event handler can be called anything
        if (EventOf(Script, @TypeOf(@field(Script, name))) != null) continue;
        comptime var hooks: []const u8 = "";
        inline for (std.enums.values(Hook)) |hook| hooks = hooks ++ " " ++ @tagName(hook);
        @compileError(script_name ++ ": " ++ name ++ " is not a hook, so it would never run. The hooks are:" ++ hooks);
    }
}

/// The script's variables as a table. Every one needs a default (what a new script starts with) and has to be one of
/// ScriptABI.FieldKind, since every one is shown in the editor and saved
fn FieldsOf(comptime Script: type, comptime script_name: []const u8) [@typeInfo(Script).@"struct".field_names.len]FieldDesc {
    const struct_info = @typeInfo(Script).@"struct";
    var fields: [struct_info.field_names.len]FieldDesc = undefined;
    for (struct_info.field_names, struct_info.field_types, struct_info.field_attrs, 0..) |name, T, attrs, i| {
        if (attrs.default_value_ptr == null) {
            @compileError(script_name ++ ": " ++ name ++ " needs a default value, what a new script starts with, e.g. " ++ name ++ ": " ++ @typeName(T) ++ " = ...");
        }
        const kind = FieldKind.Of(T) orelse @compileError(script_name ++ ": " ++ name ++ " is a " ++ @typeName(T) ++
            ", which a script variable can't be. It can be f32, i32, u32, bool, an enum, a std.StaticBitSet or std.EnumSet (up to 64 bits), IM.CollisionMask, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player or GameContext");
        fields[i] = .{
            .mName = name.ptr,
            .mKind = kind,
            .mOffset = @offsetOf(Script, name),
            .mSize = @sizeOf(T),
        };
        switch (kind) {
            .Enum => {
                const enum_info = @typeInfo(T).@"enum";
                for (enum_info.field_values, 0..) |value, index| {
                    if (value != index) @compileError(script_name ++ ": " ++ name ++ "'s enum has to number its values 0, 1, 2... in order");
                }
                const names = EnumNames(T);
                fields[i].mNames = &names;
                fields[i].mCount = names.len;
            },
            .Bits => fields[i].mCount = T.bit_length,
            .CollisionMask => fields[i].mCount = T.Bits.bit_length,
            .EnumSet => {
                //its only field is its bits, so they are where it is
                if (@sizeOf(T) != @sizeOf(std.StaticBitSet(T.len))) @compileError(script_name ++ ": " ++ name ++ "'s enum set isn't only its bits");
                const names = EnumSetNames(T);
                fields[i].mNames = &names;
                fields[i].mCount = names.len;
            },
            else => {},
        }
    }
    return fields;
}

fn EnumNames(comptime T: type) [@typeInfo(T).@"enum".field_names.len][*:0]const u8 {
    const enum_info = @typeInfo(T).@"enum";
    var names: [enum_info.field_names.len][*:0]const u8 = undefined;
    for (enum_info.field_names, 0..) |name, i| names[i] = name.ptr;
    return names;
}

/// An enum set's value names, in the order of its bits (which is its Indexer's, not always the enum's)
fn EnumSetNames(comptime T: type) [T.len][*:0]const u8 {
    var names: [T.len][*:0]const u8 = undefined;
    for (0..T.len) |i| names[i] = @tagName(T.Indexer.keyForIndex(i)).ptr;
    return names;
}
