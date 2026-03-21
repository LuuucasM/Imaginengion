const std = @import("std");

pub fn SparseSet(comptime entity_t: type, comptime index_t: type, comptime dense_t: type, comptime value_t: type) type {
    return struct {
        const Self = @This();
        //validate that index_t has less bits than entity_t
        //compute generation_t type
        mDenseToSparse: std.ArrayList(entity_t),
        mSparseToDense: std.ArrayList(dense_t),
        mValues: std.ArrayList(value_t),

        pub const empty: Self = .{
            .mDenseToSparse = .empty,
            .mSparseToDense = .empty,
            .mValues = .empty,
        };

        pub fn Deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.mDenseToSparse.deinit(allocator);
            self.mSparseToDense.deinit(allocator);
            self.mValues.deinit(allocator);
        }

        pub fn AddValue(self: *Self, allocator: std.mem.Allocator, entity_id: entity_t, value: value_t) !void {
            std.debug.assert(!self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            if (index > self.mSparseToDense.items.len) {
                try self.mSparseToDense.ensureTotalCapacity(allocator, self.mSparseToDense.capacity * 2);
                self.mSparseToDense.expandToCapacity();
            }

            const dense_ind = self.mDenseToSparse.items.len;

            try self.mDenseToSparse.append(allocator, entity_id);
            try self.mValues.append(allocator, value);

            self.mSparseToDense.items[index] = dense_ind;
        }

        pub fn HasSparse(self: Self, entity_id: entity_t) bool {
            const index = GetIndexFrom(entity_id);

            if (index >= self.mSparseToDense.items.len) return false;
            const dense_ind = self.mSparseToDense.items[index];
            return dense_ind < self.mDenseToSparse.items.len and self.mDenseToSparse.items[dense_ind] == entity_id;
        }

        pub fn Remove(self: *Self, entity_id: entity_t) void {
            std.debug.assert(self.mDenseToSparse.items.len > 0);
            std.debug.assert(self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            const dense_ind = self.mSparseToDense.items[index];
            const last_dense = self.mDenseToSparse.items.len - 1;
            const moved_dense = self.mDenseToSparse.items[self.mDenseToSparse.items.len - 1];

            _ = self.mDenseToSparse.swapRemove(dense_ind);
            _ = self.mValues.swapRemove(dense_ind);

            if (dense_ind != last_dense) {
                self.mSparseToDense.items[moved_dense] = dense_ind;
            }

            self.mSparseToDense.items[index] = self.mDenseToSparse.items.len;
        }

        pub fn GetValueBySparse(self: Self, entity_id: entity_t) *value_t {
            std.debug.assert(self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            const dense_ind = self.mSparseToDense.items[index];
            return &self.mValues.items[dense_ind];
        }

        fn GetIndexFrom(entity_id: entity_t) index_t {
            //do some math here
        }
        //fn GetGenFrom
    };
}
