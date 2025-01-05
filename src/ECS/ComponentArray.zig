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
        // Stringify: *const fn (*anyopaque, *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), u32) anyerror!void,
        // DeStringify: *const fn (*anyopaque, []const u8, u32) anyerror!usize,
        // ImguiRender: *const fn (*anyopaque, Entity) anyerror!void,
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
            // fn Stringify(ptr: *anyopaque, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entityID: u32) anyerror!void {
            //     const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            //     try self.Stringify(write_stream, entityID);
            // }
            // fn DeStringify(ptr: *anyopaque, component_string: []const u8, entityID: u32) anyerror!usize {
            //     const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            //     return try self.DeStringify(component_string, entityID);
            // }
            // fn ImguiRender(ptr: *anyopaque, entity: Entity) !void {
            //     const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            //     try self.ImguiRender(entity);
            // }
        };
        return IComponentArray{
            .ptr = obj,
            .vtable = &.{
                .Deinit = impl.Deinit,
                .DuplicateEntity = impl.DuplicateEntity,
                .HasComponent = impl.HasComponent,
                .RemoveComponent = impl.RemoveComponent,
                // .Stringify = impl.Stringify,
                // .DeStringify = impl.DeStringify,
                // .ImguiRender = impl.ImguiRender,
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
    // pub fn Stringify(self: IComponentArray, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entityID: u32) anyerror!void {
    //     try self.vtable.Stringify(self.ptr, write_stream, entityID);
    // }
    // pub fn DeStringify(self: IComponentArray, component_string: []const u8, entityID: u32) anyerror!usize {
    //     return try self.vtable.DeStringify(self.ptr, component_string, entityID);
    // }
    // pub fn ImguiRender(self: IComponentArray, entity: Entity) !void {
    //     try self.vtable.ImguiRender(self.ptr, entity);
    // }
};

pub fn ComponentArray(comptime componentType: type) type {
    return struct {
        const Self = @This();

        mComponents: SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = componentType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                .mComponents = try SparseSet(.{
                    .SparseT = u32,
                    .DenseT = u32,
                    .ValueT = componentType,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self) void {
            self.mComponents.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: u32, new_entity_id: u32) void {
            const new_dense_ind = self.mComponents.add(new_entity_id);
            self.mComponents.getValueByDense(new_dense_ind).* = self.mComponents.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: u32, component: componentType) !*componentType {
            const dense_ind = self.mComponents.add(entityID);

            const new_component = self.mComponents.getValueByDense(dense_ind);
            new_component.* = component;

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: u32) !void {
            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: u32) bool {
            return self.mComponents.hasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: u32) *componentType {
            return self.mComponents.getValueBySparse(entityID);
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.dense_count;
        }
        // pub fn Stringify(self: Self, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entityID: u32) !void {
        //     const component = self.GetComponent(entityID).*;

        //     var buffer: [260]u8 = undefined;
        //     var fba = std.heap.FixedBufferAllocator.init(&buffer);

        //     const full_component_name = @typeName(componentType);
        //     const last_dot = std.mem.lastIndexOf(u8, full_component_name, ".") orelse full_component_name.len;
        //     const component_name = full_component_name[last_dot + 1 ..];

        //     var component_string = std.ArrayList(u8).init(fba.allocator());
        //     try std.json.stringify(component, .{}, component_string.writer());

        //     try write_stream.objectField(component_name);
        //     try write_stream.write(component_string.items);
        // }
        // pub fn DeStringify(self: *Self, component_string: []const u8, entityID: u32) !usize {
        //     var buffer: [260]u8 = undefined;
        //     var fba = std.heap.FixedBufferAllocator.init(&buffer);

        //     const new_component_parsed = try std.json.parseFromSlice(componentType, fba.allocator(), component_string, .{});
        //     defer new_component_parsed.deinit();
        //     _ = try self.AddComponent(entityID, new_component_parsed.value);
        //     return componentType.Ind;
        // }
        // pub fn ImguiRender(self: *Self, entity: Entity) !void {
        //     const component = self.mComponents.getValueBySparse(entity.mEntityID);
        //     if (@hasDecl(componentType, "ImguiRender")) {
        //         try component.ImguiRender(entity);
        //     }
        // }
    };
}
