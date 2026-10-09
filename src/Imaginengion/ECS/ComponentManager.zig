const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").InternalComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const BuiltinComponentCount = @import("Components.zig").BuiltinComponentCount;
const MainObjectComponent = @import("Components.zig").MainObjectComponent;
const EntityTagComponent = @import("Components.zig").EntityTagComponent;
const ScriptTagComponent = @import("Components.zig").ScriptTagComponent;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const GroupQuery = @import("ECSManager.zig").GroupQuery;

pub fn ComponentManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        pub const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        pub const ChildComponent = @import("Components.zig").ChildComponent(entity_t);
        pub const SkipFieldComponent = @import("Components.zig").SkipFieldComponent(components_types.len);

        const Self = @This();

        const SkipFieldArrayT = InternalComponentArray(entity_t, SkipFieldComponent);

        /// A component's slot in this manager's arrays. Builtin components sit at fixed
        /// indices; every other component's slot is its position in THIS manager's
        /// components_types, which is what lets one component type be shared by several
        /// managers that list it at different positions.
        pub fn ComponentInd(comptime component_type: type) usize {
            if (component_type == ParentComponent) return ParentComponent.Ind;
            if (component_type == ChildComponent) return ChildComponent.Ind;
            if (component_type == SkipFieldComponent) return SkipFieldComponent.Ind;
            if (component_type == MainObjectComponent) return MainObjectComponent.Ind;
            if (component_type == EntityTagComponent) return EntityTagComponent.Ind;
            if (component_type == ScriptTagComponent) return ScriptTagComponent.Ind;
            inline for (components_types, 0..) |list_type, i| {
                if (list_type == component_type) return i + BuiltinComponentCount;
            }
            @compileError(@typeName(component_type) ++ " is not in this manager's components list");
        }

        pub const empty: Self = .{
            .mComponentsArrays = .empty,
        };

        mComponentsArrays: std.ArrayList(ComponentArray(entity_t)),

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {

            //add the components for entity hiearchy
            const parent_array = try ComponentArray(entity_t).Init(engine_allocator, ParentComponent);
            try self.mComponentsArrays.append(engine_allocator, parent_array);

            const child_array = try ComponentArray(entity_t).Init(engine_allocator, ChildComponent);
            try self.mComponentsArrays.append(engine_allocator, child_array);

            const skip_array = try ComponentArray(entity_t).Init(engine_allocator, SkipFieldComponent);
            try self.mComponentsArrays.append(engine_allocator, skip_array);

            const main_object_array = try ComponentArray(entity_t).Init(engine_allocator, MainObjectComponent);
            try self.mComponentsArrays.append(engine_allocator, main_object_array);

            const entity_tag_array = try ComponentArray(entity_t).Init(engine_allocator, EntityTagComponent);
            try self.mComponentsArrays.append(engine_allocator, entity_tag_array);

            const script_tag_array = try ComponentArray(entity_t).Init(engine_allocator, ScriptTagComponent);
            try self.mComponentsArrays.append(engine_allocator, script_tag_array);

            std.debug.assert(self.mComponentsArrays.items.len == BuiltinComponentCount);

            inline for (components_types) |component_type| {
                const new_component_array = try ComponentArray(entity_t).Init(engine_allocator, component_type);
                try self.mComponentsArrays.append(engine_allocator, new_component_array);
            }
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            // every component is deinitialized before any array is freed, since a component's Deinit
            // can reach into other arrays (an asset releasing a handle to another asset)
            for (self.mComponentsArrays.items) |component_array| {
                component_array.DeinitComponents(engine_context);
            }
            for (self.mComponentsArrays.items) |component_array| {
                component_array.Deinit(engine_context);
            }

            self.mComponentsArrays.deinit(engine_context.EngineAllocator());
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            // same two passes as Deinit
            for (self.mComponentsArrays.items) |component_array| {
                component_array.DeinitComponents(engine_context);
            }
            for (self.mComponentsArrays.items) |component_array| {
                component_array.clearAndFree(engine_context);
            }
        }

        /// Reuses the most recently destroyed id (generation already incremented) and gives it its SkipFieldComponent.
        /// Returns null if there are no destroyed ids to reuse. Never allocates, so it cannot fail halfway.
        pub fn ReuseFreeEntity(self: *Self) ?entity_t {
            return self._SkipFieldArray().mComponents.AddValueToFreeID(_NewSkipField());
        }

        /// Gives a never before used id its SkipFieldComponent. Only valid when ReuseFreeEntity returned null.
        pub fn CreateNewEntity(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t) !void {
            _ = try self._SkipFieldArray().AddComponent(engine_allocator, entity_id, _NewSkipField());
        }

        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) void {
            // iterate a copy of the skipfield because removing the SkipFieldComponent swap-removes it
            // inside its array, which would move another entity's skipfield under the iterator
            var entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?.mSkipField;

            var field_iter = entity_skipfield.Iterator();
            while (field_iter.next()) |comp_arr_ind| {
                if (comp_arr_ind == SkipFieldComponent.Ind) continue;
                self.mComponentsArrays.items[comp_arr_ind].DestroyEntity(engine_context, entity_id);
            }

            // remove the skipfield last so the entity stays active while its other components deinit.
            // this also puts the id on the skipfield sparse set's free list for ReuseFreeEntity
            self.mComponentsArrays.items[SkipFieldComponent.Ind].DestroyEntity(engine_context, entity_id);
        }

        fn _SkipFieldArray(self: Self) *SkipFieldArrayT {
            return @ptrCast(@alignCast(self.mComponentsArrays.items[SkipFieldComponent.Ind].mPtr));
        }

        fn _NewSkipField() SkipFieldComponent {
            var new_skipfield = SkipFieldComponent{};
            // the skipfield tracks itself so it shows up in queries and gets removed in DestroyEntity
            new_skipfield.mSkipField.ChangeToUnskipped(SkipFieldComponent.Ind);
            return new_skipfield;
        }

        /// Deep copies every component array into `other`, which must be initialized and empty.
        /// Entity ids, their generations and the free id list all carry over, so the copy holds the
        /// same entities under the same ids.
        pub fn CopyInto(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            std.debug.assert(other.mComponentsArrays.items.len == self.mComponentsArrays.items.len);

            var copied: usize = 0;
            errdefer {
                // the arrays already copied own their components, so they are emptied again
                // rather than left as a half built ECS
                for (other.mComponentsArrays.items[0..copied]) |component_array| {
                    component_array.DeinitComponents(engine_context);
                }
                for (other.mComponentsArrays.items[0..copied]) |component_array| {
                    component_array.clearAndFree(engine_context);
                }
            }
            while (copied < self.mComponentsArrays.items.len) : (copied += 1) {
                try self.mComponentsArrays.items[copied].CopyInto(engine_context, other.mComponentsArrays.items[copied]);
            }
        }

        /// Copies the original's components onto an already created entity.
        /// The hierarchy components and the entity/script tag are left out: the caller owns those,
        /// because a copy belongs in its own place in the hierarchy rather than the original's.
        pub fn DuplicateEntity(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(original_entity_id));
            std.debug.assert(self.IsActiveEntity(new_entity_id));

            // a copy of the skipfield, because the arrays below move as components are added
            var original_skipfield = self.GetComponent(SkipFieldComponent, original_entity_id).?.mSkipField;

            var field_iter = original_skipfield.Iterator();
            while (field_iter.next()) |comp_arr_ind| {
                if (comp_arr_ind == ParentComponent.Ind) continue;
                if (comp_arr_ind == ChildComponent.Ind) continue;
                if (comp_arr_ind == SkipFieldComponent.Ind) continue;
                if (comp_arr_ind == EntityTagComponent.Ind) continue;
                if (comp_arr_ind == ScriptTagComponent.Ind) continue;

                try self.mComponentsArrays.items[comp_arr_ind].DuplicateEntity(engine_context, original_entity_id, new_entity_id);

                // the copy tracks its own components, and the skipfield is refetched because that add moved things
                self.GetComponent(SkipFieldComponent, new_entity_id).?.mSkipField.ChangeToUnskipped(comp_arr_ind);
            }
        }

        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component: anytype) !*@TypeOf(component) {
            const component_t = @TypeOf(component);
            std.debug.assert(!self.HasComponent(component_t, entity_id));

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?;
            entity_skipfield.mSkipField.ChangeToUnskipped(ComponentInd(component_t));

            const internal_array: *InternalComponentArray(entity_t, component_t) = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_t)].mPtr));

            return try internal_array.AddComponent(engine_allocator, entity_id, component);
        }

        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) void {
            std.debug.assert(component_ind < components_types.len + BuiltinComponentCount);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // only removed through DestroyEntity
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?;
            entity_skipfield.mSkipField.ChangeToSkipped(component_ind);

            self.mComponentsArrays.items[component_ind].RemoveComponent(engine_context, entity_id);
        }

        pub fn HasComponent(self: Self, comptime component_type: type, entityID: entity_t) bool {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));

            return internal_array.HasComponent(entityID);
        }

        /// HasComponent for a component known only by its slot (ComponentInd) at runtime, e.g. one picked from a
        /// list stored in another component
        pub fn HasComponentInd(self: Self, component_ind: usize, entityID: entity_t) bool {
            return self.mComponentsArrays.items[component_ind].HasComponent(entityID);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entityID: entity_t) ?*component_type {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));

            return internal_array.GetComponent(entityID);
        }

        /// Every `component_type` in this manager, in dense order. Adding or removing one of that
        /// type moves them, so the slice is only good until then.
        pub fn GetComponentSlice(self: Self, comptime component_type: type) []component_type {
            const internal_array: *InternalComponentArray(entity_t, component_type) = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));
            return internal_array.mComponents.mValues.items;
        }

        pub fn ResetComponent(self: Self, engine_context: *EngineContext, entity_id: entity_t, component: anytype) void {
            const component_t = @TypeOf(component);
            std.debug.assert(self.HasComponent(component_t, entity_id));

            const internal_array_t = InternalComponentArray(entity_t, component_t);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_t)].mPtr));

            internal_array.ResetComponent(engine_context, entity_id, component);
        }

        pub fn IsActiveEntity(self: Self, entity_id: entity_t) bool {
            return self._SkipFieldArray().mComponents.HasSparse(entity_id);
        }

        /// How many entities currently have `component_type`: the length of its dense array, so no walk.
        /// Every live entity carries a SkipFieldComponent, which makes that one the total live count.
        pub fn NumWithComponent(self: Self, comptime component_type: type) usize {
            return self._InternalArray(component_type).NumOfComponents();
        }

        /// Every entity matching `query`. Each part of the query is a node (QueryNode) that answers two questions:
        /// which component lists hold every entity it can match (Sources), and whether one entity matches it
        /// (Matches). GetGroup walks the lists the whole query's node picks once, checking each entity against it
        pub fn GetGroup(self: Self, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var result: std.ArrayList(entity_t) = .empty;

            // every entity in a component's list has that component, so there is nothing to check
            if (query == .Component) {
                try result.appendSlice(allocator, self._InternalArray(query.Component).mComponents.mDenseToSparse.items);
                return result;
            }

            const Node = QueryNode(query);

            var sources: [Node.MaxSources]GroupSource = undefined;
            const source_count = Node.Sources(self, &sources);

            // there can't be more matches than entities walked, so this is the only allocation
            try result.ensureTotalCapacity(allocator, TotalEntities(sources[0..source_count]));

            const skip_array = self._SkipFieldArray();
            for (sources[0..source_count], 0..) |source, i| {
                for (source.mEntities) |entity_id| {
                    const skip_field = &skip_array.GetComponentAssume(entity_id).mSkipField;
                    // an entity in an earlier list was already checked there
                    if (InSources(sources[0..i], skip_field)) continue;
                    if (Node.Matches(skip_field)) result.appendAssumeCapacity(entity_id);
                }
            }

            return result;
        }

        /// One component's entity list for GetGroup to walk, and that component's slot for telling whether an
        /// entity is in it
        const GroupSource = struct {
            mEntities: []const entity_t,
            mInd: SkipFieldComponent.StaticSkipFieldT.SkipFieldType,
        };

        /// The node for one part of a query. Every node has:
        ///  - MaxSources: the most lists its Sources can fill, to size the buffer for it
        ///  - Sources: fills the buffer with component lists that between them hold every entity it can match,
        ///    and returns how many it filled
        ///  - Matches: whether the entity with a skipfield matches it. The query is comptime, so a whole query's
        ///    Matches unrolls into a fixed check of a few skipfield slots, e.g. has A and has B and not C
        fn QueryNode(comptime query: GroupQuery) type {
            return switch (query) {
                .Component => |component_type| ComponentNode(component_type),
                .And => |ands| AndNode(ands),
                .Or => |ors| OrNode(ors),
                .Not => |not| NotNode(not.mFirst.*, not.mSecond.*),
            };
        }

        /// One component, the leaf every other node is built from
        fn ComponentNode(comptime component_type: type) type {
            return struct {
                const MaxSources = 1;
                const Ind: SkipFieldComponent.StaticSkipFieldT.SkipFieldType = ComponentInd(component_type);

                /// its own list holds everything that has it
                fn Sources(manager: Self, sources: []GroupSource) usize {
                    sources[0] = .{
                        .mEntities = manager._InternalArray(component_type).mComponents.mDenseToSparse.items,
                        .mInd = Ind,
                    };
                    return 1;
                }

                fn Matches(skip_field: *const SkipFieldComponent.StaticSkipFieldT) bool {
                    return skip_field.IndexIsUnskipped(Ind);
                }
            };
        }

        /// Matches every side, what used to be EntityListIntersection
        fn AndNode(comptime ands: []const GroupQuery) type {
            return struct {
                const MaxSources = blk: {
                    var max: usize = 0;
                    for (ands) |and_query| max = @max(max, QueryNode(and_query).MaxSources);
                    break :blk max;
                };

                /// a match has to be in every side, so the lists of the side with the fewest entities hold them all
                fn Sources(manager: Self, sources: []GroupSource) usize {
                    var best_count = QueryNode(ands[0]).Sources(manager, sources);
                    var best_total = TotalEntities(sources[0..best_count]);
                    inline for (ands[1..]) |and_query| {
                        var side: [QueryNode(and_query).MaxSources]GroupSource = undefined;
                        const side_count = QueryNode(and_query).Sources(manager, &side);
                        const side_total = TotalEntities(side[0..side_count]);
                        if (side_total < best_total) {
                            @memcpy(sources[0..side_count], side[0..side_count]);
                            best_count = side_count;
                            best_total = side_total;
                        }
                    }
                    return best_count;
                }

                fn Matches(skip_field: *const SkipFieldComponent.StaticSkipFieldT) bool {
                    inline for (ands) |and_query| {
                        if (!QueryNode(and_query).Matches(skip_field)) return false;
                    }
                    return true;
                }
            };
        }

        /// Matches any side, what used to be EntityListUnion
        fn OrNode(comptime ors: []const GroupQuery) type {
            return struct {
                const MaxSources = blk: {
                    var total: usize = 0;
                    for (ors) |or_query| total += QueryNode(or_query).MaxSources;
                    break :blk total;
                };

                /// a match can come from any side, so it takes every side's lists. a list already taken from
                /// another side is only taken once
                fn Sources(manager: Self, sources: []GroupSource) usize {
                    var count: usize = 0;
                    inline for (ors) |or_query| {
                        var side: [QueryNode(or_query).MaxSources]GroupSource = undefined;
                        const side_count = QueryNode(or_query).Sources(manager, &side);
                        for (side[0..side_count]) |source| {
                            if (HasSource(sources[0..count], source.mInd)) continue;
                            sources[count] = source;
                            count += 1;
                        }
                    }
                    return count;
                }

                fn Matches(skip_field: *const SkipFieldComponent.StaticSkipFieldT) bool {
                    inline for (ors) |or_query| {
                        if (QueryNode(or_query).Matches(skip_field)) return true;
                    }
                    return false;
                }
            };
        }

        /// Matches the first side but not the second, what used to be EntityListDifference
        fn NotNode(comptime first: GroupQuery, comptime second: GroupQuery) type {
            return struct {
                const MaxSources = QueryNode(first).MaxSources;

                /// a match has to match the first side, so its lists hold them all
                fn Sources(manager: Self, sources: []GroupSource) usize {
                    return QueryNode(first).Sources(manager, sources);
                }

                fn Matches(skip_field: *const SkipFieldComponent.StaticSkipFieldT) bool {
                    return QueryNode(first).Matches(skip_field) and !QueryNode(second).Matches(skip_field);
                }
            };
        }

        fn TotalEntities(sources: []const GroupSource) usize {
            var total: usize = 0;
            for (sources) |source| total += source.mEntities.len;
            return total;
        }

        fn HasSource(sources: []const GroupSource, ind: SkipFieldComponent.StaticSkipFieldT.SkipFieldType) bool {
            for (sources) |source| {
                if (source.mInd == ind) return true;
            }
            return false;
        }

        /// Whether the entity with `skip_field` is in any of `sources`
        fn InSources(sources: []const GroupSource, skip_field: *const SkipFieldComponent.StaticSkipFieldT) bool {
            for (sources) |source| {
                if (skip_field.IndexIsUnskipped(source.mInd)) return true;
            }
            return false;
        }

        /// Removes from `result` every id in `list2`. Both lists have to hold ids from this ECS
        pub fn EntityListDifference(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("ComponentManager::EntityListDifference", @src());
            defer zone.Deinit();

            if (result.items.len == 0) return;

            const list2_marks = try self._MarkEntities(list2.items, allocator);
            defer allocator.free(list2_marks);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (_IsMarked(list2_marks, result.items[i])) {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                } else {
                    i += 1;
                }
            }

            result.shrinkRetainingCapacity(end_index);
        }

        /// Appends to `result` every id in `list2` it doesn't already have. Both lists have to hold ids from this ECS
        pub fn EntityListUnion(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("ComponentManager::EntityListUnion", @src());
            defer zone.Deinit();

            const result_marks = try self._MarkEntities(result.items, allocator);
            defer allocator.free(result_marks);

            try result.ensureUnusedCapacity(allocator, list2.items.len);
            for (list2.items) |entity_id| {
                if (_IsMarked(result_marks, entity_id)) continue;
                // marked as well, so a repeat inside list2 is not appended twice
                result_marks[SkipFieldArrayT.SparseSetT.GetIndexFrom(entity_id)] = entity_id;
                result.appendAssumeCapacity(entity_id);
            }
        }

        /// Keeps only the ids in `result` that are also in `list2`. Both lists have to hold ids from this ECS
        pub fn EntityListIntersection(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("ComponentManager::EntityListIntersection", @src());
            defer zone.Deinit();

            if (result.items.len == 0) return;

            const list2_marks = try self._MarkEntities(list2.items, allocator);
            defer allocator.free(list2_marks);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (_IsMarked(list2_marks, result.items[i])) {
                    i += 1;
                } else {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                }
            }

            result.shrinkRetainingCapacity(end_index);
        }

        /// One slot per entity index this ECS has ever handed out, holding the id from `list` at that index and
        /// NoEntity everywhere else. Lets the EntityList functions ask "is this id in the list" with one read
        /// (_IsMarked) instead of a hash lookup. The full id is kept rather than a bit so an id from an older
        /// generation of the same index doesn't count
        fn _MarkEntities(self: Self, list: []const entity_t, allocator: std.mem.Allocator) ![]entity_t {
            const marks = try allocator.alloc(entity_t, self._SkipFieldArray().mComponents.mSparseToDense.items.len);
            @memset(marks, NoEntity);
            for (list) |entity_id| {
                marks[SkipFieldArrayT.SparseSetT.GetIndexFrom(entity_id)] = entity_id;
            }
            return marks;
        }

        fn _IsMarked(marks: []const entity_t, entity_id: entity_t) bool {
            return marks[SkipFieldArrayT.SparseSetT.GetIndexFrom(entity_id)] == entity_id;
        }

        /// The empty mark in _MarkEntities. Its index is the largest there is, so it only clashes with a real id
        /// once an ECS has handed out every index
        const NoEntity: entity_t = std.math.maxInt(entity_t);

        fn _InternalArray(self: Self, comptime component_type: type) *InternalComponentArray(entity_t, component_type) {
            return @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));
        }
    };
}
