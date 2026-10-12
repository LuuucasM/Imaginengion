//! The engine's side of a script's variables: they live in the script's DLL (one instance per script child, see
//! ScriptExport), and everything else about them is done here from the script's variable table (ScriptABI.FieldDesc),
//! without knowing the script's type: shown in the editor, saved and loaded, copied with their object, pointed at the
//! right world, and carried over to a new build of the script.
//! An object variable (Entity, SceneLayer, Player, GameContext) is a handle into the same world as the script, saved as
//! the object's UUID and found again once that is loaded, the way SpawnPossComponent's reference is
const std = @import("std");
const ScriptABI = @import("ScriptABI.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const RefMap = @import("../ECSObjects/ECSObject.zig").RefMap;
const Serializer = @import("../Serializer/Serializer.zig");
const Inspector = @import("../UI/Inspector.zig");
const Widgets = @import("../UI/Widgets.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");
const ScriptAsset = @import("../ECSComponents/Asset/ScriptAsset.zig");
const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");

const ScriptInfo = ScriptABI.ScriptInfo;
const FieldDesc = ScriptABI.FieldDesc;
const Vec2 = MathTypes.Vec2(f32);
const Vec3 = MathTypes.Vec3(f32);
const Vec4 = MathTypes.Vec4(f32);

/// A script child's variables, and the table that says what is in them
pub const Instance = struct {
    mInfo: *const ScriptInfo,
    mData: *anyopaque,
};

/// The script asset a script child runs, if it is loaded. Never loads it
pub fn AssetOf(component: *const ScriptComponent) ?*ScriptAsset {
    const handle = component.mScriptAssetHandle;
    if (handle.mID == AssetHandle.NullObject) return null;
    return handle.mManager.GetLoadedAsset(ScriptAsset, handle.mID);
}

/// A script child's variables, null for one with none yet (its script never loaded)
pub fn InstanceOf(component: *const ScriptComponent) ?Instance {
    const id = component.mInstance orelse return null;
    const asset = AssetOf(component) orelse return null;
    return .{ .mInfo = asset.GetInfo(), .mData = asset.GetInstance(id) orelse return null };
}

/// The variable `field` in `data`, as a T
fn At(comptime T: type, data: *anyopaque, field: FieldDesc) *T {
    return @ptrCast(@alignCast(@as([*]u8, @ptrCast(data)) + field.mOffset));
}

/// Writes the variables as a JSON object, by name. An object variable is written as its object's UUID, and left out
/// when it points at nothing (or at something with no UUID, which could not be found again)
pub fn Write(info: *const ScriptInfo, data: *anyopaque, jw: anytype) !void {
    try jw.beginObject();
    for (info.Fields()) |field| {
        switch (field.mKind) {
            .F32 => try WriteField(jw, field, At(f32, data, field).*),
            .I32 => try WriteField(jw, field, At(i32, data, field).*),
            .U32 => try WriteField(jw, field, At(u32, data, field).*),
            .Bool => try WriteField(jw, field, At(bool, data, field).*),
            .Enum => {
                const index = EnumIndex(field, data);
                if (index < field.mEnumCount) try WriteField(jw, field, field.EnumName(index));
            },
            .Vec2 => {
                const v = At(Vec2, data, field).*;
                try WriteField(jw, field, [2]f32{ v.x, v.y });
            },
            .Vec3 => {
                const v = At(Vec3, data, field).*;
                try WriteField(jw, field, [3]f32{ v.x, v.y, v.z });
            },
            .Vec4 => {
                const v = At(Vec4, data, field).*;
                try WriteField(jw, field, [4]f32{ v.x, v.y, v.z, v.w });
            },
            inline .Entity, .Scene, .Player, .GameContext => |kind| {
                const object = At(kind.ObjectType(), data, field).*;
                if (object.mID == @TypeOf(object).NullObject or !object.IsActive()) continue;
                const uuid = object.GetComponent(UUIDComponent) orelse continue;
                try WriteField(jw, field, uuid.ID);
            },
        }
    }
    try jw.endObject();
}

fn WriteField(jw: anytype, field: FieldDesc, value: anytype) !void {
    try jw.objectField(field.Name());
    try jw.write(value);
}

/// Sets the variables of `script` (a script child, any of the four object types) from `values`, a JSON object Write
/// made. A variable that isn't in it, or is of another kind there (the script was changed since), keeps what it has.
/// An object variable is set once its object is loaded, see ResolveRef
pub fn Read(engine_context: *EngineContext, script: anytype, values: std.json.Value) !void {
    const component = script.GetComponent(ScriptComponent) orelse return;
    const instance = InstanceOf(component) orelse return;
    if (values != .object) return;
    for (instance.mInfo.Fields(), 0..) |field, index| {
        const value = values.object.get(field.Name()) orelse continue;
        const data = instance.mData;
        switch (field.mKind) {
            .F32 => At(f32, data, field).* = Float(value) orelse continue,
            .I32 => At(i32, data, field).* = std.math.lossyCast(i32, Float(value) orelse continue),
            .U32 => At(u32, data, field).* = std.math.lossyCast(u32, Float(value) orelse continue),
            .Bool => At(bool, data, field).* = if (value == .bool) value.bool else continue,
            .Enum => {
                if (value != .string) continue;
                for (0..field.mEnumCount) |i| {
                    if (std.mem.eql(u8, field.EnumName(i), value.string)) SetEnumIndex(field, data, i);
                }
            },
            .Vec2 => {
                const n = Floats(2, value) orelse continue;
                At(Vec2, data, field).* = .{ .x = n[0], .y = n[1] };
            },
            .Vec3 => {
                const n = Floats(3, value) orelse continue;
                At(Vec3, data, field).* = .{ .x = n[0], .y = n[1], .z = n[2] };
            },
            .Vec4 => {
                const n = Floats(4, value) orelse continue;
                At(Vec4, data, field).* = .{ .x = n[0], .y = n[1], .z = n[2], .w = n[3] };
            },
            .Entity, .Scene, .Player, .GameContext => {
                const uuid = UUIDOf(value) orelse continue;
                try engine_context.mSerializer.AddResolveReq(engine_context.EngineAllocator(), .{
                    .Requester = Serializer.Requester.Init(script),
                    .UUID = uuid,
                    .Resolve = ResolveRef,
                    .Field = @intCast(index),
                });
            },
        }
    }
}

/// Points variable number `field_index` of `requester`'s script at the object with UUID `uuid` in its world, false if
/// that isn't loaded yet
fn ResolveRef(requester: Serializer.Requester, uuid: u64, field_index: u32) bool {
    switch (requester) {
        .Bus => return true,
        inline else => |script| {
            //the script may have been removed or broken since the request was made, nothing left to resolve
            const component = script.GetComponent(ScriptComponent) orelse return true;
            const instance = InstanceOf(component) orelse return true;
            if (field_index >= instance.mInfo.mFieldCount) return true;
            const field = instance.mInfo.mFields[field_index];
            switch (field.mKind) {
                inline .Entity, .Scene, .Player, .GameContext => |kind| {
                    const object = script.mManager.GetObjectByUUID(kind.ObjectType(), uuid) orelse return false;
                    At(kind.ObjectType(), instance.mData, field).* = object;
                },
                else => {},
            }
            return true;
        },
    }
}

/// Gives the script child `to` the variables of `from`, which runs the same script: a copy of an object starting as
/// its template is (ECSObject.Core._CopyObject). Its object variables still point where `from`'s do, see RemapRefs
pub fn CopyValues(from: *const ScriptComponent, to: *const ScriptComponent) void {
    const source = InstanceOf(from) orelse return;
    const dest = InstanceOf(to) orelse return;
    if (source.mInfo != dest.mInfo) return;
    const size = source.mInfo.mDataSize;
    @memcpy(@as([*]u8, @ptrCast(dest.mData))[0..size], @as([*]const u8, @ptrCast(source.mData))[0..size]);
}

/// Points every object variable at `world`: for a copy of a whole world, where ids carry over (WorldManager.Copy)
pub fn Retarget(instance: Instance, world: *WorldManager) void {
    for (instance.mInfo.Fields()) |field| {
        switch (field.mKind) {
            inline .Entity, .Scene, .Player, .GameContext => |kind| At(kind.ObjectType(), instance.mData, field).mManager = world,
            else => {},
        }
    }
}

/// For a copy of an object put in `world` (a template's copy, a duplicate): an entity variable pointing into what was
/// copied points at its copy instead, one pointing elsewhere in `world` stays, and one pointing into another world (a
/// template's own) is cleared
pub fn RemapRefs(instance: Instance, ref_map: *const RefMap, world: *WorldManager) void {
    for (instance.mInfo.Fields()) |field| {
        switch (field.mKind) {
            inline .Entity, .Scene, .Player, .GameContext => |kind| {
                const object = At(kind.ObjectType(), instance.mData, field);
                if (object.mID == @TypeOf(object.*).NullObject) continue;
                if (kind == .Entity) {
                    if (ref_map.Get(object.*)) |copy| {
                        object.* = copy;
                        continue;
                    }
                }
                if (object.mManager != world) object.* = .uninit;
            },
            else => {},
        }
    }
}

/// Copies variables from an old build's instance into a new build's, by name: one that is still there with the same
/// kind keeps its value (an enum by its value's name), anything else keeps the new build's default
pub fn CarryOver(old_info: *const ScriptInfo, old_data: *anyopaque, new_info: *const ScriptInfo, new_data: *anyopaque) void {
    for (new_info.Fields()) |new_field| {
        const old_field = for (old_info.Fields()) |old_field| {
            if (std.mem.eql(u8, old_field.Name(), new_field.Name())) break old_field;
        } else continue;
        if (old_field.mKind != new_field.mKind) continue;

        if (new_field.mKind == .Enum) {
            const old_index = EnumIndex(old_field, old_data);
            if (old_index >= old_field.mEnumCount) continue;
            for (0..new_field.mEnumCount) |i| {
                if (std.mem.eql(u8, new_field.EnumName(i), old_field.EnumName(old_index))) SetEnumIndex(new_field, new_data, i);
            }
            continue;
        }
        if (old_field.mSize != new_field.mSize) continue;
        const from = @as([*]const u8, @ptrCast(old_data)) + old_field.mOffset;
        const to = @as([*]u8, @ptrCast(new_data)) + new_field.mOffset;
        @memcpy(to[0..new_field.mSize], from[0..new_field.mSize]);
    }
}

/// The rows that edit `script`'s variables (a script child, any of the four object types), under `parent`. `root` is
/// what is built again when a field that rebuilds is edited (see Inspector.Builder). Nothing for a script with no
/// variables, or that never loaded
pub fn BuildFields(engine_context: *EngineContext, parent: Entity, root: Entity, script: anytype, options: Widgets.Options) !void {
    const component = script.GetComponent(ScriptComponent) orelse return;
    const instance = InstanceOf(component) orelse return;
    const info = instance.mInfo;
    if (info.mFieldCount == 0) return;

    //the rows are measured from a copy, as RenderComponent does: building them can't move it
    const frame_allocator = engine_context.FrameAllocator();
    const copy = try frame_allocator.alignedAlloc(u8, .@"16", info.mDataSize);
    @memcpy(copy, @as([*]const u8, @ptrCast(instance.mData))[0..info.mDataSize]);
    const data: *anyopaque = @ptrCast(copy.ptr);

    var builder = Inspector.Builder{
        .mEngineContext = engine_context,
        .mParent = parent,
        .mRoot = root,
        .mObject = Inspector.ObjectRef.Of(script),
        .mBase = @intFromPtr(copy.ptr),
        .mResolve = ResolveFor(@TypeOf(script)),
        .mAfterEdit = &NothingAfterEdit,
        .mOptions = options,
    };
    for (info.Fields()) |field| {
        const label = Label(field.Name());
        switch (field.mKind) {
            .F32 => try builder.Float(At(f32, data, field), label, .{}),
            .I32 => try builder.Int(At(i32, data, field), label, .{}),
            .U32 => try builder.UInt(At(u32, data, field), label, .{}),
            .Bool => try builder.Bool(At(bool, data, field), label, .{}),
            .Enum => {
                const choices = try frame_allocator.alloc([]const u8, field.mEnumCount);
                for (choices, 0..) |*choice, i| choice.* = field.EnumName(i);
                const field_ptr: *u8 = @ptrCast(@as([*]u8, @ptrCast(data)) + field.mOffset);
                try builder.Choice(field_ptr, label, choices, EnumAccess(field.mSize), .{});
            },
            .Vec2 => try builder.Vec2Field(At(Vec2, data, field), label, .{}),
            .Vec3 => try builder.Vec3Field(At(Vec3, data, field), label, .{}),
            .Vec4 => try builder.Vec4Field(At(Vec4, data, field), label, .{}),
            .Entity => _ = try builder.EntityRef(At(Entity, data, field), label, .{}),
            .Scene => _ = try builder.SceneRef(At(Scene, data, field), label, .{}),
            .Player => _ = try builder.PlayerRef(At(Player, data, field), label, .{}),
            .GameContext => _ = try builder.GameContextRef(At(GameContext, data, field), label, .{}),
        }
    }
}

/// A variable's name as it is shown: mSpeed as Speed
fn Label(name: []const u8) []const u8 {
    if (name.len > 1 and name[0] == 'm' and std.ascii.isUpper(name[1])) return name[1..];
    return name;
}

/// Finds a script child's variables again, for the rows that edit them: null once it, its script or its instance has gone
fn ResolveFor(comptime object_type: type) *const fn (Inspector.ObjectRef) ?*anyopaque {
    return &struct {
        fn Resolve(object: Inspector.ObjectRef) ?*anyopaque {
            const script = @field(object, @tagName(ScriptABI.OwnerKind.Of(object_type)));
            if (!script.IsActive()) return null;
            const component = script.GetComponent(ScriptComponent) orelse return null;
            const instance = InstanceOf(component) orelse return null;
            return instance.mData;
        }
    }.Resolve;
}

/// A script's variables only matter to the script, nothing else has to catch up when one is edited
fn NothingAfterEdit(_: *EngineContext, _: Inspector.ObjectRef) anyerror!bool {
    return false;
}

/// An enum variable `size` bytes big, as the index of its value (its values are numbered 0, 1, 2... in order)
fn EnumAccess(size: u32) *const Inspector.Access {
    return switch (size) {
        1 => EnumAccessOf(u8),
        2 => EnumAccessOf(u16),
        else => EnumAccessOf(u32),
    };
}

fn EnumAccessOf(comptime Int: type) *const Inspector.Access {
    return &struct {
        const access = Inspector.Access{ .Read = ReadChoice, .Write = WriteChoice };

        fn ReadChoice(field: *anyopaque) Inspector.Value {
            return .{ .Choice = @as(*Int, @ptrCast(@alignCast(field))).* };
        }

        fn WriteChoice(_: *EngineContext, field: *anyopaque, written: Inspector.Value) anyerror!void {
            if (written != .Choice) return;
            @as(*Int, @ptrCast(@alignCast(field))).* = @intCast(written.Choice);
        }
    }.access;
}

/// Which of an enum variable's values it has. Only the bits its values need are read: an enum with a 1 bit tag is kept
/// in a byte whose other bits mean nothing
fn EnumIndex(field: FieldDesc, data: *anyopaque) usize {
    const bytes = @as([*]const u8, @ptrCast(data)) + field.mOffset;
    var raw: u32 = 0;
    for (0..field.mSize) |i| raw |= @as(u32, bytes[i]) << @intCast(i * 8);
    const bits = std.math.log2_int_ceil(u32, @max(field.mEnumCount, 1));
    const mask: u32 = if (bits >= 32) std.math.maxInt(u32) else (@as(u32, 1) << @intCast(bits)) - 1;
    return raw & mask;
}

fn SetEnumIndex(field: FieldDesc, data: *anyopaque, index: usize) void {
    const bytes = @as([*]u8, @ptrCast(data)) + field.mOffset;
    const value: u32 = @intCast(index);
    for (0..field.mSize) |i| bytes[i] = @truncate(value >> @intCast(i * 8));
}

fn Float(value: std.json.Value) ?f32 {
    return switch (value) {
        .float => |f| @floatCast(f),
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

fn Floats(comptime n: usize, value: std.json.Value) ?[n]f32 {
    if (value != .array or value.array.items.len != n) return null;
    var floats: [n]f32 = undefined;
    for (value.array.items, 0..) |item, i| floats[i] = Float(item) orelse return null;
    return floats;
}

/// A UUID as JSON has it: a u64 too big for an i64 comes as a number string
fn UUIDOf(value: std.json.Value) ?u64 {
    return switch (value) {
        .integer => |i| if (i < 0) null else @intCast(i),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}
