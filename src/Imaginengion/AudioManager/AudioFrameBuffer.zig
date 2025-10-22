const std = @import("std");
const Audio2D = @import("Audio2D.zig");
const Audio3D = @import("Audio3D.zig");

pub const AudioFrame = struct {
    Emissions2D: Audio2D.Emissions2D,
    Emissions3D: Audio3D.Emissions3D,
};

pub const AudioFrameBuffer = union(enum) {
    E_DoubleBuffer: DoubleBuffer,
    E_TripleBuffer: TripleBuffer,

    pub fn Init(self: *AudioFrameBuffer) !void {
        switch (self.*) {
            inline else => |buffer| return try buffer.Init(),
        }
    }
    pub fn Deinit(self: *AudioFrameBuffer) void {
        switch (self.*) {
            inline else => |buffer| return buffer.Deinit(),
        }
    }
    pub fn GetWriteBuffer(self: *AudioFrameBuffer) *AudioFrame {
        switch (self.*) {
            inline else => |buffer| return buffer.GetWriteBuffer(),
        }
    }
    pub fn GetReadBuffer(self: *AudioFrameBuffer) *AudioFrame {
        switch (self.*) {
            inline else => |buffer| return buffer.GetReadBuffer(),
        }
    }
    pub fn FinishWriting(self: *AudioFrameBuffer) void {
        switch (self.*) {
            inline else => |buffer| return buffer.FinishWriting(),
        }
    }
    pub fn FinishReading(self: *AudioFrameBuffer) void {
        switch (self.*) {
            inline else => |buffer| return buffer.FinishReading(),
        }
    }
};

pub const DoubleBuffer = struct {
    _Buffer: [2]AudioFrame = .{},
    _WriteIndex: u1 = 0,
    _ReadIndex: u1 = 1,
    _SwapInUse: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn Init(self: *DoubleBuffer) !void {
        _ = self;
    }
    pub fn Deinit(self: *DoubleBuffer) void {
        _ = self;
    }
    pub fn GetWriteBuffer(self: *DoubleBuffer) *AudioFrame {
        return &self._Buffer[self._WriteIndex];
    }
    pub fn GetReadBuffer(self: *DoubleBuffer) *AudioFrame {
        while (self._SwapInUse.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }

        return &self._Buffer[self._ReadIndex];
    }
    pub fn FinishWriting(self: *DoubleBuffer) void {
        while (self._SwapInUse.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }

        const tmp = self._WriteIndex;
        self._WriteIndex = self._ReadIndex;
        self._ReadIndex = tmp;

        self._SwapInUse.store(false, .release);
    }
    pub fn FinishReading(self: *DoubleBuffer) void {
        self._SwapInUse.store(false, .release);
    }
};

pub const TripleBuffer = struct {
    _Buffer: [3]AudioFrame = .{},
    _WriteIndex: u2 = 0,
    _ReadIndex: u2 = 1,
    _PendingIndex: u2 = 2,
    _SwapInUse: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn Init(self: *TripleBuffer) !void {
        _ = self;
    }
    pub fn Deinit(self: *TripleBuffer) void {
        _ = self;
    }
    pub fn GetWriteBuffer(self: *TripleBuffer) *AudioFrame {
        return &self._Buffer[self._WriteIndex];
    }
    pub fn GetReadBuffer(self: *TripleBuffer) *AudioFrame {
        return &self._Buffer[self._ReadIndex];
    }
    pub fn FinishWriting(self: *TripleBuffer) void {
        while (self._SwapInUse.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }

        const tmp = self._WriteIndex;
        self._WriteIndex = self._PendingIndex;
        self._PendingIndex = tmp;

        self._SwapInUse.store(false, .release);
    }
    pub fn FinishReading(self: *TripleBuffer) void {
        while (self._SwapInUse.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }

        const tmp = self._ReadIndex;
        self._ReadIndex = self._PendingIndex;
        self._PendingIndex = tmp;

        self._SwapInUse.store(false, .release);
    }
};
