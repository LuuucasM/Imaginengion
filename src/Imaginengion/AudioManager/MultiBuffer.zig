const std = @import("std");

pub fn MultiBuffers(comptime T: type) type {
    return union(enum) {
        const Self = @This();

        E_DoubleBuffer: DoubleBuffer(T),
        E_TripleBuffer: TripleBuffer(T),

        pub fn Init(self: *Self) !void {
            switch (self.*) {
                inline else => |buffer| return try buffer.Init(),
            }
        }
        pub fn Deinit(self: *Self) void {
            switch (self.*) {
                inline else => |buffer| return buffer.Deinit(),
            }
        }
        pub fn GetWriteBuffer(self: *Self) *T {
            switch (self.*) {
                inline else => |buffer| return buffer.GetWriteBuffer(),
            }
        }
        pub fn GetReadBuffer(self: *Self) *T {
            switch (self.*) {
                inline else => |buffer| return buffer.GetReadBuffer(),
            }
        }
        pub fn FinishWriting(self: *Self) void {
            switch (self.*) {
                inline else => |buffer| return buffer.FinishWriting(),
            }
        }
        pub fn FinishReading(self: *Self) void {
            switch (self.*) {
                inline else => |buffer| return buffer.FinishReading(),
            }
        }
    };
}

pub fn DoubleBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        _Buffer: [2]T = .{},
        _WriteIndex: u1 = 0,
        _ReadIndex: u1 = 1,
        _SwapInUse: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub fn Init(self: *Self) !void {
            _ = self;
        }
        pub fn Deinit(self: *Self) void {
            _ = self;
        }
        pub fn GetWriteBuffer(self: *Self) *T {
            return &self._Buffer[self._WriteIndex];
        }
        pub fn GetReadBuffer(self: *Self) *T {
            while (self._SwapInUse.swap(true, .acquire)) {
                std.atomic.spinLoopHint();
            }

            return &self._Buffer[self._ReadIndex];
        }
        pub fn FinishWriting(self: *Self) void {
            while (self._SwapInUse.swap(true, .acquire)) {
                std.atomic.spinLoopHint();
            }

            const tmp = self._WriteIndex;
            self._WriteIndex = self._ReadIndex;
            self._ReadIndex = tmp;

            self._SwapInUse.store(false, .release);
        }
        pub fn FinishReading(self: *Self) void {
            self._SwapInUse.store(false, .release);
        }
    };
}

pub fn TripleBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        _Buffer: [3]T = .{},
        _WriteIndex: u2 = 0,
        _ReadIndex: u2 = 1,
        _PendingIndex: u2 = 2,
        _SwapInUse: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub fn Init(self: *Self) !void {
            _ = self;
        }
        pub fn Deinit(self: *Self) void {
            _ = self;
        }
        pub fn GetWriteBuffer(self: *Self) *T {
            return &self._Buffer[self._WriteIndex];
        }
        pub fn GetReadBuffer(self: *Self) *T {
            return &self._Buffer[self._ReadIndex];
        }
        pub fn FinishWriting(self: *Self) void {
            while (self._SwapInUse.swap(true, .acquire)) {
                std.atomic.spinLoopHint();
            }

            const tmp = self._WriteIndex;
            self._WriteIndex = self._PendingIndex;
            self._PendingIndex = tmp;

            self._SwapInUse.store(false, .release);
        }
        pub fn FinishReading(self: *Self) void {
            while (self._SwapInUse.swap(true, .acquire)) {
                std.atomic.spinLoopHint();
            }

            const tmp = self._ReadIndex;
            self._ReadIndex = self._PendingIndex;
            self._PendingIndex = tmp;

            self._SwapInUse.store(false, .release);
        }
    };
}
