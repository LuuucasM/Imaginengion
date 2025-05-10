const std = @import("std");

pub fn CircularBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        _Buffer: [size]T = std.mem.zeroes([size]T),
        _Head: usize = 0,
        _Count: usize = 0,

        pub const LookBackIterator = struct {
            _BufferPtr: *[size]T,
            _Current: usize,
            _remaining: usize,
            pub fn Next(self: LookBackIterator) ?T {
                if (self._remaining == 0) return;
                const value = self._BufferPtr.*[self._Current];
                self._Current = if (self._Current == 0) size - 1 else self._Current - 1;
                return value;
            }
        };

        pub fn Peak(self: Self) T {
            return self._Buffer[self._Head];
        }

        pub fn Push(self: Self, entry: T) void {
            self._Buffer[self._Head] = entry;
            self._Head = (self._Head + 1) % size;
            self._Count += 1;
        }

        pub fn Lookback(self: Self) ?T {
            const ind = (self._Head + size - 1) % size;
            return self._Buffer[ind];
        }

        pub fn LookbackIter(self: Self) LookBackIterator {
            return LookBackIterator{
                ._BufferPtr = &self._Buffer,
                ._Current = self._Head,
                ._remaining = if (self._Count < size) self._Count else size,
            };
        }
    };
}
