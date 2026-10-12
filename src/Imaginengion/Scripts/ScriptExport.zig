//! The half of a script's DLL nobody writes. `zig build script` builds a script around a small generated root that
//! exports `&Exports(Script, name).info` (see build_script.zig), and everything the engine needs comes from looking at
//! the script's struct at compile time:
//! - its variables, as a table of names, kinds and offsets (FieldDesc) the engine edits, saves and copies them with
//! - its hooks: any of ScriptABI.Hook it has a function for, each wrapped in a C-callable function that finds the
//!   variables for the instance it is run on
//! - where the instances are kept: one sparse set per DLL, by the instance id the engine hands it, each instance in an
//!   allocation of its own so it stays put
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
const MathTypes = @import("../Math/MathTypes.zig");

const Hook = ScriptABI.Hook;
const OwnerKind = ScriptABI.OwnerKind;
const FieldKind = ScriptABI.FieldKind;
const FieldDesc = ScriptABI.FieldDesc;
const ScriptInfo = ScriptABI.ScriptInfo;
const ScriptResult = ScriptABI.ScriptResult;

/// Everything the DLL of `Script` (a script file's struct) exports. `script_name` is only for messages
pub fn Exports(comptime Script: type, comptime script_name: []const u8) type {
    const owner_kind = comptime OwnerOf(Script, script_name);
    const Owner = owner_kind.Type();
    const fields = comptime FieldsOf(Script, script_name);

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
        };

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
            const result = @call(.auto, @field(Script, @tagName(hook)), .{ self, engine_context, owner.* } ++ args);
            if (@typeInfo(@TypeOf(result)) == .error_union) {
                return result catch |err| {
                    std.log.err("{s}.{s}: {s}", .{ script_name, @tagName(hook), @errorName(err) });
                    return .Continue;
                };
            }
            return result;
        }
    };
}

/// An object handle comes over the DLL boundary by pointer, the hook gets it as a value
fn FromAbi(value: anytype) if (@TypeOf(value) == *const Entity) Entity else @TypeOf(value) {
    return if (@TypeOf(value) == *const Entity) value.* else value;
}

/// The object type the script goes on, from its hooks' third parameter: every hook has to agree, and has to be one that
/// object type has
fn OwnerOf(comptime Script: type, comptime script_name: []const u8) OwnerKind {
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
    return owner orelse @compileError(script_name ++ ": has none of the hook functions, so nothing would ever run it. Add one, e.g. pub fn OnUpdate(self: *@This(), engine_context: *EngineContext, owner: Entity) !ScriptResult");
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
    for (@typeInfo(Script).@"struct".decl_names) |name| {
        if (name.len < 3 or !std.mem.startsWith(u8, name, "On") or !std.ascii.isUpper(name[2])) continue;
        if (@typeInfo(@TypeOf(@field(Script, name))) != .@"fn") continue;
        if (std.meta.stringToEnum(Hook, name) != null) continue;
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
        const kind = KindOf(T) orelse @compileError(script_name ++ ": " ++ name ++ " is a " ++ @typeName(T) ++
            ", which a script variable can't be. It can be f32, i32, u32, bool, an enum, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player or GameContext");
        fields[i] = .{
            .mName = name.ptr,
            .mKind = kind,
            .mOffset = @offsetOf(Script, name),
            .mSize = @sizeOf(T),
        };
        if (kind == .Enum) {
            const enum_info = @typeInfo(T).@"enum";
            for (enum_info.field_values, 0..) |value, index| {
                if (value != index) @compileError(script_name ++ ": " ++ name ++ "'s enum has to number its values 0, 1, 2... in order");
            }
            const names = EnumNames(T);
            fields[i].mEnumNames = &names;
            fields[i].mEnumCount = names.len;
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

fn KindOf(comptime T: type) ?FieldKind {
    return switch (T) {
        f32 => .F32,
        i32 => .I32,
        u32 => .U32,
        bool => .Bool,
        MathTypes.Vec2(f32) => .Vec2,
        MathTypes.Vec3(f32) => .Vec3,
        MathTypes.Vec4(f32) => .Vec4,
        Entity => .Entity,
        Scene => .Scene,
        Player => .Player,
        GameContext => .GameContext,
        else => if (@typeInfo(T) == .@"enum" and switch (@sizeOf(T)) {
            1, 2, 4 => true,
            else => false,
        }) .Enum else null,
    };
}
