const std = @import("std");

pub fn Stack(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        items: [size]T = undefined,
        len: usize = 0,

        pub fn Push(self: *Self, value: T) void {
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn Pop(self: *Self) T {
            self.len -= 1;
            return self.items[self.len];
        }

        pub fn Clear(self: *Self) void {
            self.len = 0;
        }

        pub fn IsEmpty(self: *Self) bool {
            return self.len == 0;
        }

        pub fn IsFull(self: *Self) bool {
            return self.len >= size;
        }

        pub fn Count(self: *Self) usize {
            return self.len;
        }
    };
}
