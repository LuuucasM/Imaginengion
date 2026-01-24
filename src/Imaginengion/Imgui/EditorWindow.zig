const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ComponentCategory = @import("../ECS/ECSManager.zig").ComponentCategory;
const EntityComponentsList = @import("../GameObjects/Components.zig").ComponentsList;
const SceneComponentsList = @import("../Scene/SceneComponents.zig").ComponentsList;
const EditorWindow = @This();

mEntity: Entity,
mPtr: *anyopaque,
mName: []const u8,
mComponentID: u32,
mComponentCategory: ComponentCategory,
mVTable: *const VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque, *EngineContext) anyerror!void,
};

pub fn Init(obj: anytype, entity: Entity) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    _ValidateObj(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .one);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const impl = struct {
        fn EditorRender(ptr: *anyopaque, engine_context: *EngineContext) !void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            try self.EditorRender(engine_context);
        }
    };

    return EditorWindow{
        .mEntity = entity,
        .mPtr = obj,
        .mName = Ptr.Name,
        .mComponentID = Ptr.Ind,
        .mComponentCategory = Ptr.Category,
        .mVTable = &.{
            .EditorRender = impl.EditorRender,
        },
    };
}

pub fn EditorRender(self: EditorWindow, engine_context: *EngineContext) !void {
    try self.mVTable.EditorRender(self.mPtr, engine_context);
}

pub fn GetComponentName(self: EditorWindow) []const u8 {
    return self.mName;
}

pub fn GetComponentID(self: EditorWindow) u32 {
    return self.mComponentID;
}

pub fn GetComponentCategory(self: EditorWindow) ComponentCategory {
    return self.mComponentCategory;
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
