const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").ComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const HashSet = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;

pub const GroupQuery = union(enum) {
    And: []const GroupQuery,
    Or: []const GroupQuery,
    Not: struct {
        mFirst: GroupQuery,
        mSecond: GroupQuery,
    },
    Component: type,
};

pub fn ComponentManager(entity_t: type, component_type_size: usize) type {
    return struct {
        const Self = @This();
        mComponentsArrays: std.ArrayList(ComponentArray(entity_t)),
        mEntitySkipField: SparseSet(.{
            .SparseT = entity_t,
            .DenseT = entity_t,
            .ValueT = StaticSkipField(component_type_size),
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),
        mECSAllocator: std.mem.Allocator,

        pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_list: []const type) !Self {
            var new_component_manager = Self{
                .mComponentsArrays = std.ArrayList(ComponentArray(entity_t)){},
                .mEntitySkipField = try SparseSet(.{
                    .SparseT = entity_t,
                    .DenseT = entity_t,
                    .ValueT = StaticSkipField(component_type_size),
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(ECSAllocator, 20, 10),
                .mECSAllocator = ECSAllocator,
            };

            inline for (components_list) |component_type| {
                const new_component_array = try ComponentArray(entity_t).Init(ECSAllocator, component_type);
                try new_component_manager.mComponentsArrays.append(ECSAllocator, new_component_array);
            }

            return new_component_manager;
        }

        pub fn Deinit(self: *Self) void {
            //delete component arrays
            for (self.mComponentsArrays.items) |component_array| {
                component_array.Deinit();
            }

            self.mComponentsArrays.deinit(self.mECSAllocator);
            self.mEntitySkipField.deinit();
        }

        pub fn clearAndFree(self: *Self) void {
            for (self.mComponentsArrays.items) |component_array| {
                component_array.clearAndFree();
            }
            self.mEntitySkipField.clear();
        }

        pub fn CreateEntity(self: *Self, entityID: entity_t) !void {
            std.debug.assert(!self.mEntitySkipField.HasSparse(entityID));
            const dense_ind = self.mEntitySkipField.add(entityID);
            self.mEntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(component_type_size).Init(.AllSkip);
        }

        pub fn DestroyEntity(self: *Self, entityID: entity_t) !void {
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));

            const entity_skipfield = self.mEntitySkipField.getValueBySparse(entityID);

            var i: usize = entity_skipfield.mSkipField[0];
            while (i < entity_skipfield.mSkipField.len) {
                try self.mComponentsArrays.items[i].RemoveComponent(entityID);
                i += 1;
                i += entity_skipfield.mSkipField[i];
            }
            _ = self.mEntitySkipField.remove(entityID);
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            std.debug.assert(self.mEntitySkipField.HasSparse(original_entity_id));
            std.debug.assert(self.mEntitySkipField.HasSparse(new_entity_id));

            const original_skipfield = self.mEntitySkipField.getValueBySparse(original_entity_id);
            const new_skipfield = self.mEntitySkipField.getValueBySparse(new_entity_id);
            @memcpy(&new_skipfield.mSkipField, &original_skipfield.mSkipField);

            var i: usize = original_skipfield.mSkipField[0];
            while (i < original_skipfield.mSkipField.len) {
                self.mComponentsArrays.items[i].DuplicateEntity(original_entity_id, new_entity_id);
                i += 1;
                i += original_skipfield.mSkipField[i];
            }
        }

        pub fn AddComponent(self: *Self, comptime component_type: type, entityID: entity_t, component: ?component_type) !*component_type {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            std.debug.assert(!self.HasComponent(component_type, entityID));

            self.mEntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(component_type.Ind);

            return try @as(*InternalComponentArray(entity_t, component_type), @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr))).AddComponent(entityID, component);
        }

        pub fn RemoveComponent(self: *Self, comptime component_type: type, entityID: entity_t) !void {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            std.debug.assert(self.HasComponent(component_type, entityID));

            self.mEntitySkipField.getValueBySparse(entityID).ChangeToSkipped(component_type.Ind);

            return try self.mComponentsArrays.items[component_type.Ind].RemoveComponent(entityID);
        }

        pub fn HasComponent(self: Self, comptime component_type: type, entityID: entity_t) bool {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            return @as(*InternalComponentArray(entity_t, component_type), @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr))).HasComponent(entityID);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entityID: entity_t) *component_type {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            std.debug.assert(self.HasComponent(component_type, entityID));

            return @as(*InternalComponentArray(entity_t, component_type), @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr))).GetComponent(entityID);
        }

        pub fn GetGroup(self: Self, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            switch (query) {
                .Component => |component_type| {
                    std.debug.assert(@hasDecl(component_type, "Ind"));
                    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
                    return try @as(*InternalComponentArray(entity_t, component_type), @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr))).GetAllEntities(allocator);
                },
                .Not => |not| {
                    var result = try self.GetGroup(not.mFirst, allocator);
                    var second = try self.GetGroup(not.mSecond, allocator);
                    defer second.deinit(allocator);
                    try self.EntityListDifference(&result, second, allocator);
                    return result;
                },
                .Or => |ors| {
                    var result = try self.GetGroup(ors[0], allocator);
                    inline for (ors[1..]) |or_query| {
                        var intermediate = try self.GetGroup(or_query, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListUnion(&result, intermediate, allocator);
                    }
                    return result;
                },
                .And => |ands| {
                    var result = try self.GetGroup(ands[0], allocator);
                    inline for (ands[1..]) |and_query| {
                        var intermediate = try self.GetGroup(and_query, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListIntersection(&result, intermediate, allocator);
                    }
                    return result;
                },
            }
        }

        pub fn EntityListDifference(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            _ = self;
            if (result.items.len == 0) return;

            var list2_set = HashSet(entity_t).init(allocator);
            defer list2_set.deinit();
            _ = try list2_set.appendSlice(list2.items);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (list2_set.contains(result.items[i]) == true) {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                } else {
                    i += 1;
                }
            }

            result.shrinkAndFree(allocator, end_index);
        }

        pub fn EntityListUnion(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            _ = self;

            var result_set = HashSet(entity_t).init(allocator);
            defer result_set.deinit();
            try result_set.appendSlice(result.items);

            for (list2.items) |entity_id| {
                if (result_set.contains(entity_id) == false) {
                    result.append(allocator, entity_id);
                }
            }
        }

        pub fn EntityListIntersection(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            _ = self;
            if (result.items.len == 0) return;

            var list2_set = HashSet(entity_t).init(allocator);
            defer list2_set.deinit();
            _ = try list2_set.appendSlice(list2.items);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (list2_set.contains(result.items[i]) == true) {
                    i += 1;
                } else {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                }
            }

            result.shrinkAndFree(allocator, end_index);
        }
    };
}
