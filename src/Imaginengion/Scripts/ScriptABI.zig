//! What the engine and a script's DLL agree on. A script is a plain struct (its variables) with hook functions
//! (OnUpdate, OnCollisionBegin, ...). Its DLL is built around it by ScriptExport.Exports, which hands the engine one
//! ScriptInfo: which object type the script goes on, its hooks, and a table of its variables (FieldDesc) that the
//! engine shows in the editor, saves and copies without knowing the script's type. Everything here crosses the DLL
//! boundary, so it is extern or a pointer
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const KeyboardPressedEvent = @import("../Events/WindowEventData.zig").KeyboardPressedEvent;
const PointerEvent = @import("../Events/PointerEventData.zig").PointerEvent;
const UIEvent = @import("../Events/UIEventData.zig").UIEvent;
const CollisionInfo = @import("../Physics/Collisions.zig").CollisionInfo;
const PreSolveInfo = @import("../Physics/Collisions.zig").PreSolveInfo;

/// What a hook hands back: whether what it ran for goes on to the next one in line, or stops with it
pub const ScriptResult = enum(u8) {
    /// this script dealt with it: nothing after it in line gets it
    Handled = 0,
    /// on to the next: the object's other scripts with this hook, the scenes below for a key, the parents for a click
    Continue = 1,
};

/// Which of the four object types a script goes on, from the type of its hooks' owner parameter
pub const OwnerKind = enum(u8) {
    Entity,
    Scene,
    Player,
    GameContext,

    pub fn Of(comptime object_type: type) OwnerKind {
        return switch (object_type) {
            Entity => .Entity,
            Scene => .Scene,
            Player => .Player,
            GameContext => .GameContext,
            else => @compileError(@typeName(object_type) ++ " is not an object type a script can go on"),
        };
    }

    pub fn Type(comptime self: OwnerKind) type {
        return switch (self) {
            .Entity => Entity,
            .Scene => Scene,
            .Player => Player,
            .GameContext => GameContext,
        };
    }
};

/// The functions a script can have, each run by the engine at its own time. A script has any of them its owner type
/// takes (see Takes): the name is what says when it runs
pub const Hook = enum(u8) {
    /// once a frame
    OnUpdate,
    /// every key pressed, the script checks which
    OnKeyPressed,
    /// the owner's collider started touching another
    OnCollisionBegin,
    /// the owner's collider stopped touching another
    OnCollisionEnd,
    /// from the middle of the physics step, before the solver acts on a solid contact
    OnPreSolve,
    /// at the start of every physics step
    OnPhysicsUpdate,
    /// every pointer event sent to the owner
    OnPointerEvent,
    /// every UI event sent to the owner
    OnUIEvent,
    /// once, when the owning scene is loaded and the game is running
    OnSceneStart,
    /// once, when the game starts
    OnGameStart,

    /// Whether a script on an object of type `owner` can have this hook
    pub fn Takes(self: Hook, owner: OwnerKind) bool {
        return switch (owner) {
            .Entity => switch (self) {
                .OnUpdate, .OnKeyPressed, .OnCollisionBegin, .OnCollisionEnd, .OnPreSolve, .OnPhysicsUpdate, .OnPointerEvent, .OnUIEvent => true,
                else => false,
            },
            .Scene => switch (self) {
                .OnUpdate, .OnSceneStart, .OnPhysicsUpdate => true,
                else => false,
            },
            .Player => switch (self) {
                .OnUpdate, .OnKeyPressed => true,
                else => false,
            },
            .GameContext => switch (self) {
                .OnUpdate, .OnGameStart => true,
                else => false,
            },
        };
    }

    /// What the hook is handed after (self, engine context, owner), as the script writes it
    pub fn Params(comptime self: Hook) []const type {
        return switch (self) {
            .OnUpdate, .OnSceneStart, .OnGameStart => &.{},
            .OnKeyPressed => &.{*const KeyboardPressedEvent},
            //the other entity, and the contact as the owner sees it
            .OnCollisionBegin, .OnCollisionEnd => &.{ Entity, *const CollisionInfo },
            //the contact can be switched off through the info
            .OnPreSolve => &.{ Entity, *PreSolveInfo },
            //the length of the step in seconds
            .OnPhysicsUpdate => &.{f32},
            .OnPointerEvent => &.{*const PointerEvent},
            .OnUIEvent => &.{*const UIEvent},
        };
    }
};

pub const HOOK_COUNT = std.enums.values(Hook).len;

/// One of a hook's parameters as it crosses into the DLL: an object handle goes by pointer, it is not extern
fn AbiParam(comptime T: type) type {
    return if (T == Entity) *const Entity else T;
}

/// The function a script's DLL hands the engine for `hook` on an owner of type `owner_type`: the engine context, the
/// owner, the script's variables (the instance), then the hook's own parameters
pub fn HookFn(comptime owner_type: type, comptime hook: Hook) type {
    const params = hook.Params();
    var types: [3 + params.len]type = undefined;
    types[0] = *EngineContext;
    types[1] = *const owner_type;
    types[2] = *anyopaque;
    for (params, 0..) |param, i| types[3 + i] = AbiParam(param);
    const final_types = types;
    const attrs: [final_types.len]std.builtin.Type.Fn.ParamAttributes = @splat(.{});
    return *const @Fn(&final_types, &attrs, ScriptResult, .{ .@"callconv" = .c });
}

/// The kinds of variable a script can have. Anything else is a compile error naming the variable
pub const FieldKind = enum(u8) {
    F32,
    I32,
    U32,
    Bool,
    /// an enum whose values are 0, 1, 2... in order, 8, 16 or 32 bits
    Enum,
    Vec2,
    Vec3,
    Vec4,
    Entity,
    Scene,
    Player,
    GameContext,

    /// The object type of an object variable: a handle to an object in the same world, saved as the object's UUID
    pub fn ObjectType(comptime self: FieldKind) type {
        return switch (self) {
            .Entity => Entity,
            .Scene => Scene,
            .Player => Player,
            .GameContext => GameContext,
            else => @compileError(@tagName(self) ++ " is not an object variable"),
        };
    }
};

/// One of a script's variables
pub const FieldDesc = extern struct {
    mName: [*:0]const u8,
    mKind: FieldKind,
    /// where it is in the script's struct, and how many bytes it takes
    mOffset: u32,
    mSize: u32,
    /// an enum's value names, in value order
    mEnumNames: ?[*]const [*:0]const u8 = null,
    mEnumCount: u32 = 0,

    pub fn Name(self: FieldDesc) []const u8 {
        return std.mem.span(self.mName);
    }

    pub fn EnumName(self: FieldDesc, index: usize) []const u8 {
        return std.mem.span(self.mEnumNames.?[index]);
    }
};

/// What a script's DLL hands the engine (its exported IM_GetScriptInfo). The DLL keeps every instance of the script's
/// variables itself, one per script child, by an instance id the engine picks
pub const ScriptInfo = extern struct {
    mOwner: OwnerKind,
    /// a HookFn for each hook the script has, null for the rest
    mHooks: [HOOK_COUNT]?*const anyopaque,
    mFields: [*]const FieldDesc,
    mFieldCount: u32,
    mDataSize: u32,
    /// makes instance `id`, a copy of `copy_from` (another instance's variables) or the script's defaults when null.
    /// False if there was no memory for it
    mNewInstance: *const fn (engine_context: *EngineContext, id: u32, copy_from: ?*const anyopaque) callconv(.c) bool,
    mFreeInstance: *const fn (engine_context: *EngineContext, id: u32) callconv(.c) void,
    /// null for an id that has no instance. Stays where it is until it is freed, or the script is swapped for a new build
    mGetInstance: *const fn (id: u32) callconv(.c) ?*anyopaque,
    /// frees what the DLL keeps the instances in, before it is unloaded
    mDeinit: *const fn (engine_context: *EngineContext) callconv(.c) void,

    pub fn Fields(self: *const ScriptInfo) []const FieldDesc {
        return self.mFields[0..self.mFieldCount];
    }

    pub fn HasHook(self: *const ScriptInfo, hook: Hook) bool {
        return self.mHooks[@intFromEnum(hook)] != null;
    }
};

/// The symbol a script's DLL exports its ScriptInfo through
pub const INFO_SYMBOL = "IM_GetScriptInfo";
pub const GetInfoFn = *const fn () callconv(.c) *const ScriptInfo;
