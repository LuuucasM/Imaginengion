const std = @import("std");

pub fn Stack(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        items: [size]T = undefined,
        len: usize = 0,

        pub fn push(self: *Self, value: T) void {
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn pop(self: *Self) T {
            self.len -= 1;
            return self.items[self.len];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.len == 0;
        }

        pub fn isFull(self: *Self) bool {
            return self.len >= size;
        }

        pub fn count(self: *Self) usize {
            return self.len;
        }
    };
}
