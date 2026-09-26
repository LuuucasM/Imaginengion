const std = @import("std");
const SPSCRingBuffer = @import("SPSCRingBuffer.zig").SPSCRingBuffer;

const Ring = SPSCRingBuffer(u32, 8);

fn Sequence(comptime start: u32, comptime len: usize) [len]u32 {
    var items: [len]u32 = undefined;
    for (&items, 0..) |*item, i| item.* = start + @as(u32, @intCast(i));
    return items;
}

test "a new ring is empty" {
    var ring: Ring = .default;

    try std.testing.expect(ring.IsEmpty());
    try std.testing.expect(!ring.IsFull());
    try std.testing.expectEqual(0, ring.AvailableRead());
    try std.testing.expectEqual(8, ring.AvailableWrite());
    try std.testing.expectEqual(null, ring.Pop());

    var out: [4]u32 = undefined;
    try std.testing.expectEqual(0, ring.PopSlice(&out));
}

test "single items come out in the order they went in" {
    var ring: Ring = .default;

    try std.testing.expect(ring.Push(1));
    try std.testing.expect(ring.Push(2));
    try std.testing.expect(ring.Push(3));

    try std.testing.expectEqual(1, ring.Pop());
    try std.testing.expectEqual(2, ring.Pop());
    try std.testing.expectEqual(3, ring.Pop());
    try std.testing.expectEqual(null, ring.Pop());
}

test "push fails once full and works again after a pop" {
    var ring: Ring = .default;

    for (0..8) |i| try std.testing.expect(ring.Push(@intCast(i)));
    try std.testing.expect(ring.IsFull());
    try std.testing.expectEqual(0, ring.AvailableWrite());
    try std.testing.expect(!ring.Push(99));

    try std.testing.expectEqual(0, ring.Pop());
    try std.testing.expect(ring.Push(99));
    try std.testing.expect(ring.IsFull());
}

test "slices larger than the free space are cut short" {
    var ring: Ring = .default;
    const items = Sequence(0, 12);

    try std.testing.expectEqual(8, ring.PushSlice(&items));
    try std.testing.expectEqual(0, ring.PushSlice(&items));

    //asking for more than is buffered only returns what is there
    var out: [12]u32 = undefined;
    try std.testing.expectEqual(8, ring.PopSlice(&out));
    try std.testing.expectEqualSlices(u32, items[0..8], out[0..8]);
}

test "slices that cross the end of the buffer wrap around to the start" {
    var ring: Ring = .default;
    var out: [8]u32 = undefined;

    //move both indices to 6 so the next 5 items land in slots 6, 7, 0, 1, 2
    const first = Sequence(0, 6);
    try std.testing.expectEqual(6, ring.PushSlice(&first));
    try std.testing.expectEqual(6, ring.PopSlice(out[0..6]));

    const wrapped = Sequence(100, 5);
    try std.testing.expectEqual(5, ring.PushSlice(&wrapped));
    try std.testing.expectEqual(5, ring.AvailableRead());

    //popped in two parts so the read also has to wrap, once with a split and once without
    try std.testing.expectEqual(3, ring.PopSlice(out[0..3]));
    try std.testing.expectEqualSlices(u32, wrapped[0..3], out[0..3]);
    try std.testing.expectEqual(2, ring.PopSlice(out[0..2]));
    try std.testing.expectEqualSlices(u32, wrapped[3..5], out[0..2]);
    try std.testing.expect(ring.IsEmpty());
}

test "a slice ending exactly at the end of the buffer does not wrap" {
    var ring: Ring = .default;
    var out: [8]u32 = undefined;

    const first = Sequence(0, 5);
    _ = ring.PushSlice(&first);
    _ = ring.PopSlice(out[0..5]);

    //slots 5, 6, 7: the end index masks to 0
    const tail = Sequence(50, 3);
    try std.testing.expectEqual(3, ring.PushSlice(&tail));
    try std.testing.expectEqual(3, ring.PopSlice(out[0..3]));
    try std.testing.expectEqualSlices(u32, &tail, out[0..3]);
}

test "a full-size slice can start in the middle of the buffer" {
    var ring: Ring = .default;
    var out: [8]u32 = undefined;

    const first = Sequence(0, 3);
    _ = ring.PushSlice(&first);
    _ = ring.PopSlice(out[0..3]);

    //start == end after masking, which has to take the wrapping path
    const full = Sequence(200, 8);
    try std.testing.expectEqual(8, ring.PushSlice(&full));
    try std.testing.expect(ring.IsFull());
    try std.testing.expectEqual(8, ring.PopSlice(&out));
    try std.testing.expectEqualSlices(u32, &full, &out);
}

test "indices keep working when they wrap past the largest usize" {
    var ring: Ring = .default;
    const near_max = std.math.maxInt(usize) - 2;
    ring.mWriteIndex.raw = near_max;
    ring.mReadIndex.raw = near_max;

    const items = Sequence(0, 6);
    try std.testing.expectEqual(6, ring.PushSlice(&items));
    try std.testing.expectEqual(6, ring.AvailableRead());
    try std.testing.expectEqual(2, ring.AvailableWrite());
    try std.testing.expect(ring.Push(6));
    try std.testing.expect(ring.Push(7));
    try std.testing.expect(ring.IsFull());

    var out: [8]u32 = undefined;
    try std.testing.expectEqual(8, ring.PopSlice(&out));
    try std.testing.expectEqualSlices(u32, &Sequence(0, 8), &out);
    try std.testing.expect(ring.IsEmpty());
}

test "a producer and consumer on separate threads see every item once, in order" {
    const StressRing = SPSCRingBuffer(u32, 64);
    const TOTAL: u32 = 200_000;

    const Producer = struct {
        fn Run(ring: *StressRing) void {
            var chunk: [17]u32 = undefined; //odd size so chunks land across the wrap point at many offsets
            var next: u32 = 0;
            while (next < TOTAL) {
                const len = @min(chunk.len, TOTAL - next);
                for (chunk[0..len], 0..) |*item, i| item.* = next + @as(u32, @intCast(i));

                var pushed: usize = 0;
                while (pushed < len) {
                    const n = ring.PushSlice(chunk[pushed..len]);
                    if (n == 0) std.atomic.spinLoopHint();
                    pushed += n;
                }
                next += @intCast(len);
            }
        }
    };

    var ring: StressRing = .default;
    const producer = try std.Thread.spawn(.{}, Producer.Run, .{&ring});

    var out: [23]u32 = undefined;
    var expected: u32 = 0;
    var mismatch = false;
    while (expected < TOTAL) {
        const n = ring.PopSlice(&out);
        if (n == 0) std.atomic.spinLoopHint();
        for (out[0..n]) |item| {
            if (item != expected) mismatch = true;
            expected += 1;
        }
    }
    producer.join();

    try std.testing.expect(!mismatch);
    try std.testing.expect(ring.IsEmpty());
}
