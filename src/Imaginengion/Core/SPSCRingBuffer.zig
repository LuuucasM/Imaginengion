const std = @import("std");

pub fn SPSCRingBuffer(comptime T: type, comptime size: usize) type {
    comptime {
        if (size == 0) {
            @compileError("size of SPSCRingBuffer must be greater than 0!");
        }
        if (size & (size - 1) != 0) {
            @compileError("size of SPSCRingBuffer must be power of 2!");
        }
    }

    return struct {
        const Self = @This();
        const mask = size - 1;

        mBuffer: [size]T = std.mem.zeroes([size]T),
        mWriteIndex: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        mReadIndex: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        pub fn Init() Self {
            return Self{};
        }

        pub fn Push(self: *Self, item: T) bool {
            const write = self.mWriteIndex.load(.monotonic);
            const read = self.mReadIndex.load(.acquire);

            if (write - read >= size) {
                return false;
            }

            self.mBuffer[write & mask] = item;
            self.mWriteIndex.store(write + 1, .release);
        }

        pub fn PushSlice(self: *Self, items: []const T) usize {
            const write = self.mWriteIndex.load(.monotonic);
            const read = self.mReadIndex.load(.acquire);

            const available = size - (write - read);
            const write_size = @min(items.len, available);

            if (write_size == 0) {
                return 0;
            }

            const start_index = write & mask;
            const end_index = (write + write_size) & mask;

            if (start_index < end_index or end_index == 0) {
                @memcpy(self.mBuffer[start_index .. start_index + write_size], items[0..write_size]);
            } else { //we have to wrap so we cant write in 1 continuous chunk it must be 2
                const first_slice = size - start_index;
                const second_slice = write_size - first_slice;

                @memcpy(self.mBuffer[start_index..size], items[0..first_slice]);
                @memcpy(self.mBuffer[0..second_slice], items[first_slice..write_size]);
            }

            self.mWriteIndex.store(write + write_size, .release);
            return write_size;
        }

        pub fn Pop(self: *Self) ?T {
            const write = self.mWriteIndex.load(.acquire);
            const read = self.mReadIndex.load(.monotonic);

            if (write == read) {
                return null;
            }

            const item = self.mBuffer[read & mask];
            self.mReadIndex.store(read + 1, .release);
            return item;
        }

        pub fn PopSlice(self: *Self, buffer: []T) usize {
            const write = self.mWriteIndex.load(.acquire);
            const read = self.mReadIndex.load(.monotonic);

            const available = write - read;
            const read_size = @min(buffer.len, available);

            if (read_size == 0) {
                return 0;
            }

            const start_index = read & mask;
            const end_index = (read + read_size) & mask;

            if (start_index < end_index or end_index == 0) {
                @memcpy(buffer[0..read_size], self.mBuffer[start_index .. start_index + read_size]);
            } else { //we have to wrap around the buffer to read
                const first_slice = size - start_index;
                const second_slice = read_size - first_slice;

                @memcpy(buffer[0..first_slice], self.mBuffer[start_index..size]);
                @memcpy(buffer[first_slice..read_size], self.mBuffer[0..second_slice]);
            }

            self.mReadIndex.store(read + read_size, .release);
            return read_size;
        }
    };
}
