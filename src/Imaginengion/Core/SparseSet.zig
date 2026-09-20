const std = @import("std");

/// `track_free_ids` turns on the free id list. When on, removed ids (with their generation incremented)
/// are kept in the unused capacity of mDenseToSparse, which is always there because every Remove shrinks
/// the dense array by one:
///
///     mDenseToSparse: [ live ids ... | free ids (newest first) | spare ]
///                                     ^ items.len              ^ items.len + mFreeCount
///
/// Reusing an id must pop it and add it back in one step (AddValueToFreeID), so AddValue asserts the
/// free list is empty: any plain add while ids are free would overwrite the top of the list.
pub fn SparseSet(comptime entity_t: type, comptime index_t: type, comptime value_t: type, comptime track_free_ids: bool) type {
    return struct {
        const Self = @This();

        const entity_bits = @bitSizeOf(entity_t);
        const index_bits = @bitSizeOf(index_t);
        const gen_bits = entity_bits - index_bits;
        const dense_t = std.math.IntFittingRange(0, std.math.maxInt(index_t) + 1);
        comptime {
            std.debug.assert(index_bits <= entity_bits);
        }
        const generation_t = @Int(.unsigned, gen_bits);

        mDenseToSparse: std.ArrayList(entity_t),
        mFreeCount: if (track_free_ids) usize else void,
        mSparseToDense: std.ArrayList(dense_t),
        mValues: std.ArrayList(value_t),

        pub const empty: Self = .{
            .mDenseToSparse = .empty,
            .mFreeCount = if (track_free_ids) 0 else {},
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
            // new ids are only allowed once every free id has been reused, see AddValueToFreeID
            if (track_free_ids) std.debug.assert(self.mFreeCount == 0);

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

        /// Pops the most recently freed id and adds `value` to it in one step.
        /// Returns null if there are no free ids. Never allocates: the dense arrays already held
        /// items.len + mFreeCount entries before those ids were removed, so the capacity is still there.
        pub fn AddValueToFreeID(self: *Self, value: value_t) ?entity_t {
            if (!track_free_ids) @compileError("AddValueToFreeID requires track_free_ids");
            if (self.mFreeCount == 0) return null;

            const entity_id = self.mDenseToSparse.unusedCapacitySlice()[0];
            std.debug.assert(!self.HasSparse(entity_id));

            self.mFreeCount -= 1;

            const dense_ind = self.mDenseToSparse.items.len;

            self.mDenseToSparse.appendAssumeCapacity(entity_id);
            self.mValues.appendAssumeCapacity(value);

            self.mSparseToDense.items[GetIndexFrom(entity_id)] = @intCast(dense_ind);

            return entity_id;
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
            const moved_entity_id = self.mDenseToSparse.items[self.mDenseToSparse.items.len - 1];

            _ = self.mDenseToSparse.swapRemove(dense_ind);
            _ = self.mValues.swapRemove(dense_ind);

            if (dense_ind != last_dense) {
                self.mSparseToDense.items[GetIndexFrom(moved_entity_id)] = dense_ind;
            }

            if (track_free_ids) {
                //push onto the free list, which now starts one slot earlier
                const freelist = self.mDenseToSparse.unusedCapacitySlice();
                std.debug.assert(freelist.len > self.mFreeCount);
                freelist[0] = NextGeneration(entity_id);
                self.mFreeCount += 1;
            }

            self.mSparseToDense.items[index] = @intCast(self.mDenseToSparse.items.len);
        }

        /// returns the same index with the generation bits incremented (wrapping back to 0)
        pub fn NextGeneration(entity_id: entity_t) entity_t {
            var gen = GetGenFrom(entity_id);
            if (gen == std.math.maxInt(generation_t)) gen = 0 else gen += 1;

            return (@as(entity_t, @intCast(gen)) << index_bits) | @as(entity_t, @intCast(GetIndexFrom(entity_id)));
        }

        pub fn GetValueBySparse(self: Self, entity_id: entity_t) *value_t {
            std.debug.assert(self.HasSparse(entity_id));

            const index = GetIndexFrom(entity_id);

            const dense_ind = self.mSparseToDense.items[index];
            return &self.mValues.items[dense_ind];
        }

        /// Copies this set into `other`, which must be empty. Ids, their generations and the free id
        /// list all carry over, so `other` holds the same ids and hands out the same ones next.
        /// Values are copied as they are, so a value that owns memory is left aliasing this set's
        /// and has to be replaced by the caller.
        pub fn CopyInto(self: Self, allocator: std.mem.Allocator, other: *Self) !void {
            std.debug.assert(other.mDenseToSparse.items.len == 0);
            std.debug.assert(other.mValues.items.len == 0);

            const free_count: usize = if (track_free_ids) self.mFreeCount else 0;

            // the free ids live in the unused capacity of the dense arrays, so both of them are
            // grown to cover the live entries and the free ones sitting behind them
            const dense_capacity = self.mDenseToSparse.items.len + free_count;
            try other.mDenseToSparse.ensureTotalCapacity(allocator, dense_capacity);
            try other.mValues.ensureTotalCapacity(allocator, dense_capacity);
            try other.mSparseToDense.resize(allocator, self.mSparseToDense.items.len);

            other.mDenseToSparse.appendSliceAssumeCapacity(self.mDenseToSparse.items);
            other.mValues.appendSliceAssumeCapacity(self.mValues.items);
            @memcpy(other.mSparseToDense.items, self.mSparseToDense.items);

            if (track_free_ids) {
                @memcpy(
                    other.mDenseToSparse.unusedCapacitySlice()[0..free_count],
                    self.mDenseToSparse.unusedCapacitySlice()[0..free_count],
                );
                other.mFreeCount = free_count;
            }
        }

        pub fn clearAndFree(self: *Self, allocator: std.mem.Allocator) void {
            self.mDenseToSparse.clearAndFree(allocator);
            self.mSparseToDense.clearAndFree(allocator);
            self.mValues.clearAndFree(allocator);
            if (track_free_ids) self.mFreeCount = 0;
        }

        pub fn GetIndexFrom(entity_id: entity_t) index_t {
            //do some math here
            const index_mask: entity_t = std.math.maxInt(index_t);
            return @intCast(entity_id & index_mask);
        }
        //fn GetGenFrom
        pub fn GetGenFrom(entity_id: entity_t) generation_t {
            return @intCast(entity_id >> index_bits);
        }
    };
}
