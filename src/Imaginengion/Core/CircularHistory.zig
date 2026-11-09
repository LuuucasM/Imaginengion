const std = @import("std");

/// The last `size` items appended, the oldest written over first. `contains` needs T to have an Equals function; the
/// rest works on any T, plain numbers included
pub fn CircularHistory(comptime T: type, comptime size: usize) type {
    comptime {
        if ((size & (size - 1)) != 0) {
            @compileError(@typeName(T) ++ "Capacity must be a power of two");
        }
    }

    return struct {
        buffer: [size]T,
        insert_idx: usize,
        count: usize,

        const Self = @This();
        const mask = size - 1;
        pub const capacity = size;

        pub const empty: Self = .{
            .buffer = std.mem.zeroes([size]T),
            .insert_idx = 0,
            .count = 0,
        };

        pub fn append(self: *Self, item: T) void {
            self.buffer[self.insert_idx] = item;
            self.insert_idx = (self.insert_idx + 1) & mask;

            if (self.count < size) {
                self.count += 1;
            }
        }

        pub fn contains(self: *const Self, item: T) bool {
            if (!@hasDecl(T, "Equals")) @compileError(@typeName(T) ++ "Type needs 'Equals' function for comparison");
            if (self.count == 0) return false;
            for (self.buffer[0..self.count]) |element| {
                if (element.Equals(item)) {
                    return true;
                }
            }
            return false;
        }

        /// Every item held, in no particular order: for sums, maxes and the like, where the order doesn't matter
        pub fn items(self: *const Self) []const T {
            return self.buffer[0..self.count];
        }

        /// The item appended last. Only while there is one
        pub fn latest(self: *const Self) T {
            std.debug.assert(self.count > 0);
            return self.buffer[(self.insert_idx + size - 1) & mask];
        }

        pub fn clear(self: *Self) void {
            self.insert_idx = 0;
            self.count = 0;
        }
    };
}
