const std = @import("std");

pub fn SparseSet(comptime entity_t: type, comptime index_t: type, comptime value_t: type) type {
    return struct {
        const Self = @This();

        const entity_bits = @bitSizeOf(entity_t);
        const index_bits = @bitSizeOf(index_t);
        const gen_bits = entity_bits - index_bits;
        const dense_t = std.math.IntFittingRange(0, std.math.maxInt(index_t) + 1);
        comptime {
            std.debug.assert(index_bits <= entity_bits);
        }
        const generation_t = std.meta.Int(.unsigned, gen_bits);

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

        pub fn AddValue(self: *Self, allocator: std.mem.Allocator, entity_id: entity_t, value: value_t) !*value_t {
            std.debug.assert(!self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            if (index >= self.mSparseToDense.items.len) {
                const index_u = @as(usize, @intCast(index));
                try self.mSparseToDense.ensureTotalCapacity(allocator, index_u + (index_u / 2) + 1);
                self.mSparseToDense.expandToCapacity();
            }

            const dense_ind = self.mDenseToSparse.items.len;

            try self.mDenseToSparse.append(allocator, entity_id);
            try self.mValues.append(allocator, value);

            self.mSparseToDense.items[index] = @intCast(dense_ind);

            return &self.mValues.items[self.mValues.items.len - 1];
        }

        pub fn HasSparse(self: Self, entity_id: entity_t) bool {
            const index = GetIndexFrom(entity_id);

            if (index >= self.mSparseToDense.items.len) return false;
            const dense_ind = self.mSparseToDense.items[index];
            return dense_ind < self.mDenseToSparse.items.len and self.mDenseToSparse.items[dense_ind] == entity_id;
        }

        pub fn HasFreeEntity(self: Self) ?entity_t {
            if (self.mDenseToSparse.items.len < self.mDenseToSparse.capacity) {
                return self.mDenseToSparse.unusedCapacitySlice()[0];
            }
            return null;
        }

        pub fn Remove(self: *Self, entity_id: entity_t) void {
            std.debug.assert(self.mDenseToSparse.items.len > 0);
            std.debug.assert(self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            const dense_ind = self.mSparseToDense.items[index];
            const last_dense = self.mDenseToSparse.items.len - 1;
            const moved_entity_id = self.mDenseToSparse.items[self.mDenseToSparse.items.len - 1];

            _ = self.mDenseToSparse.swapRemove(dense_ind);
            _ = self.mValues.swapRemove(dense_ind);

            if (dense_ind != last_dense) {
                self.mSparseToDense.items[GetIndexFrom(moved_entity_id)] = dense_ind;
            }

            //add one to the generation bits
            var gen = GetGenFrom(entity_id);
            if (gen == std.math.maxInt(generation_t)) gen = 0 else gen += 1;

            const freelist = self.mDenseToSparse.unusedCapacitySlice();
            std.debug.assert(freelist.len > 0);
            freelist[0] = (@as(entity_t, @intCast(gen)) << index_bits) | @as(entity_t, @intCast(index));

            self.mSparseToDense.items[index] = @intCast(self.mDenseToSparse.items.len);
        }

        pub fn GetValueBySparse(self: Self, entity_id: entity_t) *value_t {
            std.debug.assert(self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            const dense_ind = self.mSparseToDense.items[index];
            return &self.mValues.items[dense_ind];
        }

        pub fn clearAndFree(self: *Self, allocator: std.mem.Allocator) void {
            self.mDenseToSparse.clearAndFree(allocator);
            self.mSparseToDense.clearAndFree(allocator);
            self.mValues.clearAndFree(allocator);
        }

        fn GetIndexFrom(entity_id: entity_t) index_t {
            //do some math here
            const index_mask: entity_t = std.math.maxInt(index_t);
            return @intCast(entity_id & index_mask);
        }
        //fn GetGenFrom
        fn GetGenFrom(entity_id: entity_t) generation_t {
            return @intCast(entity_id >> index_bits);
        }
    };
}
