const std = @import("std");

pub fn CircularHistory(comptime T: type, comptime size: usize) type {
    comptime {
        if ((size & (size - 1)) != 0) {
            @compileError("Capacity must be a power of two");
        }
    }

    return struct {
        buffer: [size]T,
        insert_idx: usize,
        count: usize,

        const Self = @This();
        const mask = size - 1;

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
            if (self.count == 0) return false;
            for (self.buffer[0..self.count]) |element| {
                if (element == item) {
                    return true;
                }
            }
            return false;
        }

        pub fn clear(self: *Self) void {
            self.insert_idx = 0;
            self.count = 0;
        }
    };
}
