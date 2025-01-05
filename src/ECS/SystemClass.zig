const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
//const ComponentList = @import("Components.zig").ComponentsList;
const BitFieldType = @import("ComponentManager.zig").BitFieldType;
pub const ISystem = struct {
    mPtr: *anyopaque,
    mVTable: *const VTab,
    mEntities: Set(u32),
    mBitField: BitFieldType,

    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        OnUpdate: *const fn (*anyopaque, Set(u32)) anyerror!void,
    };
    pub fn Init(obj: anytype, allocator: std.mem.Allocator, system_types: []const type) ISystem {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .Pointer);
        std.debug.assert(PtrInfo.Pointer.size == .One);
        std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct);

        const impl = struct {
            fn Deinit(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.Deinit();
                alloc.destroy(self);
            }
            fn OnUpdate(ptr: *anyopaque, entities: Set(u32)) !void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.OnUpdate(entities);
            }
        };
        var new_sys = ISystem{
            .mPtr = obj,
            .mVTable = &.{
                .Deinit = impl.Deinit,
                .OnUpdate = impl.OnUpdate,
            },
            .mEntities = Set(u32).init(allocator),
            .mBitField = 0,
        };
        inline for (system_types) |component_type| {
            new_sys.mBitField |= 1 << component_type.Ind;
        }
        return new_sys;
    }
    pub fn Deinit(self: *ISystem, allocator: std.mem.Allocator) void {
        self.mVTable.Deinit(self.mPtr, allocator);
        self.mEntities.deinit();
    }
    pub fn OnUpdate(self: *ISystem, entities: Set(u32)) void {
        self.mVTable.OnUpdate(self.mPtr, entities);
    }
};
