const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const ComponentManager = @import("ComponentManager.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const EComponent = @import("../GameObjects/Components.zig").EComponents;

pub const ISystem = struct {
    mPtr: *anyopaque,
    mVTable: *const VTab,
    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        OnUpdate: *const fn (*anyopaque, component_manager: ComponentManager) anyerror!void,
        AddEntity: *const fn (*anyopaque, u32) anyerror!void,
        RemoveEntity: *const fn (*anyopaque, u32) void,
        GetComponentField: *const fn (*anyopaque) StaticSkipField(32 + 1),
    };

    pub fn Init(obj: anytype) ISystem {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .pointer);
        std.debug.assert(PtrInfo.pointer.size == .one);
        std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

        const impl = struct {
            fn Deinit(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.Deinit();
                alloc.destroy(self);
            }
            fn OnUpdate(ptr: *anyopaque, component_manager: ComponentManager) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.OnUpdate(component_manager);
            }
            fn AddEntity(ptr: *anyopaque, entity_id: u32) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.AddEntity(entity_id);
            }
            fn RemoveEntity(ptr: *anyopaque, entity_id: u32) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.RemoveEntity(entity_id);
            }
            fn GetComponentField(ptr: *anyopaque) StaticSkipField(32 + 1) {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                return self.GetComponentField();
            }
        };
        return ISystem{
            .mPtr = obj,
            .mVTable = &.{
                .Deinit = impl.Deinit,
                .OnUpdate = impl.OnUpdate,
                .AddEntity = impl.AddEntity,
                .RemoveEntity = impl.RemoveEntity,
                .GetComponentField = impl.GetComponentField,
            },
        };
    }

    pub fn Deinit(self: *ISystem, allocator: std.mem.Allocator) void {
        self.mVTable.Deinit(self.mPtr, allocator);
        self.mEntities.deinit();
    }

    pub fn OnUpdate(self: *ISystem, component_manager: ComponentManager) !void {
        try self.mVTable.OnUpdate(self.mPtr, component_manager);
    }

    pub fn AddEntity(self: *ISystem, entity_id: u32) !void {
        try self.mVTable.AddEntity(self.mPtr, entity_id);
    }

    pub fn RemoveEntity(self: *ISystem, entity_id: u32) void {
        self.mVTable.RemoveEntity(self.mPtr, entity_id);
    }

    pub fn GetComponentField(self: ISystem) StaticSkipField(32 + 1) {
        return self.mVTable.GetComponentField(self.mPtr);
    }
};
