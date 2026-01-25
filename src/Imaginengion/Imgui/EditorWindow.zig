const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const EntityNameComponent = EntityComponents.NameComponent;
const EntityComponentsList = EntityComponents.ComponentsList;
const SceneComponentsList = @import("../Scene/SceneComponents.zig").ComponentsList;
const EditorWindow = @This();

mEntity: Entity,
mPtr: *anyopaque,
mComponentName: []const u8,
mComponentID: u32,
mVTable: *const VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque, *EngineContext) anyerror!void,
};

pub fn Init(obj: anytype, entity: Entity) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .one);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const ObjT = PtrInfo.pointer.child;
    _ValidateObj(ObjT);

    const impl = struct {
        fn EditorRender(ptr: *anyopaque, engine_context: *EngineContext) !void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            try self.EditorRender(engine_context);
        }
    };

    return EditorWindow{
        .mEntity = entity,
        .mPtr = obj,
        .mComponentName = ObjT.Name,
        .mComponentID = ObjT.Ind,
        .mVTable = &.{
            .EditorRender = impl.EditorRender,
        },
    };
}

pub fn EditorRender(self: EditorWindow, engine_context: *EngineContext) !void {
    try self.mVTable.EditorRender(self.mPtr, engine_context);
}

pub fn GetEntityName(self: EditorWindow) []const u8 {
    return self.mEntity.GetComponent(EntityNameComponent).?.*.mName.items;
}

pub fn GetComponentName(self: EditorWindow) []const u8 {
    return self.mComponentName;
}

pub fn GetComponentID(self: EditorWindow) u32 {
    return self.mComponentID;
}
fn _ValidateObj(obj_type: type) void {
    const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(obj_type)});
    comptime var is_valid_type: bool = false;

    inline for (EntityComponentsList) |comp_t| {
        if (obj_type == comp_t) {
            is_valid_type = true;
        }
    }

    inline for (SceneComponentsList) |comp_t| {
        if (obj_type == comp_t) {
            is_valid_type = true;
        }
    }
    if (is_valid_type == false) {
        @compileError("that type can not be used EditorWindow. Type: " ++ type_name);
    }
}
