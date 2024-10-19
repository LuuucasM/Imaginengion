const std = @import("std");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

pub const IComponentArray = struct {
    ptr: *anyopaque,
    vtable: *const VTab,
    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        DuplicateEntity: *const fn (*anyopaque, u32, u32) void,
        HasComponent: *const fn (*anyopaque, u32) bool,
        RemoveComponent: *const fn (*anyopaque, u32) anyerror!void,
        Stringify: *const fn (*anyopaque, *std.ArrayList(u8), u32) anyerror!void,
    };

    pub fn Init(obj: anytype) IComponentArray {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .Pointer);
        std.debug.assert(PtrInfo.Pointer.size == .One);
        std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct);

        const impl = struct {
            fn Deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.Deinit();
                allocator.destroy(self);
            }
            fn DuplicateEntity(ptr: *anyopaque, original_entity_id: u32, new_entity_id: u32) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.DuplicateEntity(original_entity_id, new_entity_id);
            }
            fn HasComponent(ptr: *anyopaque, entityID: u32) bool {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                return self.HasComponent(entityID);
            }
            fn RemoveComponent(ptr: *anyopaque, entityID: u32) anyerror!void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.RemoveComponent(entityID);
            }
            fn Stringify(ptr: *anyopaque, out: *std.ArrayList(u8), entityID: u32) anyerror!void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.Stringify(out, entityID);
            }
        };
        return IComponentArray{
            .ptr = obj,
            .vtable = &.{
                .Deinit = impl.Deinit,
                .DuplicateEntity = impl.DuplicateEntity,
                .HasComponent = impl.HasComponent,
                .RemoveComponent = impl.RemoveComponent,
                .Stringify = impl.Stringify,
            },
        };
    }

    pub fn Deinit(self: IComponentArray, allocator: std.mem.Allocator) void {
        self.vtable.Deinit(self.ptr, allocator);
    }
    pub fn DuplicateEntity(self: IComponentArray, original_entity_id: u32, new_entity_id: u32) void {
        self.vtable.DuplicateEntity(self.ptr, original_entity_id, new_entity_id);
    }
    pub fn RemoveComponent(self: IComponentArray, entityID: u32) anyerror!void {
        try self.vtable.RemoveComponent(self.ptr, entityID);
    }
    pub fn HasComponent(self: IComponentArray, entityID: u32) bool {
        return self.vtable.HasComponent(self.ptr, entityID);
    }
    pub fn Stringify(self: IComponentArray, out: *std.ArrayList(u8), entityID: u32) anyerror!void {
        try self.vtable.Stringify(self.ptr, out, entityID);
    }
};

pub fn ComponentArray(comptime componentType: type) type {
    return struct {
        const Self = @This();

        _Components: SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = componentType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                ._Components = try SparseSet(.{
                    .SparseT = u32,
                    .DenseT = u32,
                    .ValueT = componentType,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self) void {
            self._Components.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: u32, new_entity_id: u32) void {
            const new_dense_ind = self._Components.add(new_entity_id);
            self._Components.getValueByDense(new_dense_ind).* = self._Components.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: u32, component: componentType) !*componentType {
            const dense_ind = self._Components.add(entityID);

            const new_component = self._Components.getValueByDense(dense_ind);
            new_component.* = component;

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: u32) !void {
            self._Components.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: u32) bool {
            return self._Components.hasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: u32) *componentType {
            return self._Components.getValueBySparse(entityID);
        }
        pub fn Stringify(self: Self, out: *std.ArrayList(u8), entityID: u32) !void {
            var write_stream = std.json.writeStream(out.writer(), .{ .whitespace = .indent_2 });
            const component = self.GetComponent(entityID).*;

            var buffer: [260]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);

            var component_string = std.ArrayList(u8).init(fba.allocator());

            try std.json.stringify(component, .{}, component_string.writer());
            try write_stream.objectField(@typeName(componentType));
            try write_stream.write(component_string.items);
        }
    };
}
