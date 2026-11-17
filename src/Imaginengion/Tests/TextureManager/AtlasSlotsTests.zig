//! Where textures go in the atlas (TextureManager/AtlasSlots.zig): a buddy allocator over each layer with bins on top for
//! the small sizes, and the u32 handle the shaders read a texture's place from (AtlasHandle.zig). CPU only. Run with
//! `zig build test-engine`.
const std = @import("std");

const AtlasHandle = @import("../../TextureManager/AtlasHandle.zig");
const AtlasSlots = @import("../../TextureManager/AtlasSlots.zig");

const allocator = std.testing.allocator;

/// The class of a slot `size` pixels across
fn ClassOfSlot(size: u32) u32 {
    return std.math.log2_int(u32, size / AtlasHandle.CELL);
}

test "a handle holds its layer, its cell and its class, and the shaders read the pixel it starts at" {
    const handle = AtlasHandle.Make(37, 5, 63, 3);
    try std.testing.expectEqual(37, AtlasHandle.Layer(handle));
    try std.testing.expectEqual(5, AtlasHandle.CellX(handle));
    try std.testing.expectEqual(63, AtlasHandle.CellY(handle));
    try std.testing.expectEqual(3, AtlasHandle.Class(handle));
    try std.testing.expectEqual(5 * 64 + AtlasHandle.PADDING, AtlasHandle.PixelX(handle));

    //a slot keeps its padding on every side
    try std.testing.expectEqual(0, AtlasHandle.ClassOf(60, 1));
    try std.testing.expectEqual(1, AtlasHandle.ClassOf(61, 1));
    try std.testing.expectEqual(4, AtlasHandle.ClassOf(659, 641));
    try std.testing.expectEqual(6, AtlasHandle.ClassOf(3088, 3088));
    try std.testing.expectEqual(null, AtlasHandle.ClassOf(4093, 4));
}

test "small textures of one size share a page of 8 x 8 slots, and every size can share one layer" {
    var slots: AtlasSlots = .{};
    defer slots.Deinit(allocator);
    try slots.AddLayer(allocator);

    //two 64s side by side in one page
    const first = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    const second = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    try std.testing.expectEqual(AtlasHandle.CellX(first) + 1, AtlasHandle.CellX(second));
    try std.testing.expectEqual(AtlasHandle.CellY(first), AtlasHandle.CellY(second));

    //a 128 takes a page of its own; a 256, 512, 1024 and 2048 take blocks just their size: all still in the one layer
    const handles = [_]u32{
        (try slots.Alloc(allocator, ClassOfSlot(128))).?,
        (try slots.Alloc(allocator, ClassOfSlot(256))).?,
        (try slots.Alloc(allocator, ClassOfSlot(512))).?,
        (try slots.Alloc(allocator, ClassOfSlot(1024))).?,
        (try slots.Alloc(allocator, ClassOfSlot(2048))).?,
    };
    for (handles) |handle| try std.testing.expectEqual(0, AtlasHandle.Layer(handle));

    const usage = slots.Usage();
    try std.testing.expectEqual(2, usage[0].Used);
    try std.testing.expectEqual(64, usage[0].Capacity);
    try std.testing.expectEqual(1, usage[0].Pages);
    try std.testing.expectEqual(1, usage[1].Pages);
    try std.testing.expectEqual(0, usage[2].Pages);
    try std.testing.expectEqual(1, usage[5].Used);

    //the 65th 64 starts a second page
    for (0..62) |_| _ = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    try std.testing.expectEqual(1, slots.Usage()[0].Pages);
    _ = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    try std.testing.expectEqual(2, slots.Usage()[0].Pages);

    //a whole layer is not there: the layer is in use
    try std.testing.expectEqual(null, try slots.Alloc(allocator, ClassOfSlot(4096)));
}

test "freeing merges blocks back up, so a layer emptied of small textures takes a whole one again" {
    var slots: AtlasSlots = .{};
    defer slots.Deinit(allocator);
    try slots.AddLayer(allocator);

    const tiny = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    const medium = (try slots.Alloc(allocator, ClassOfSlot(1024))).?;
    const big = (try slots.Alloc(allocator, ClassOfSlot(2048))).?;
    try std.testing.expectEqual(0, slots.TrailingFreeLayers());

    slots.Free(tiny);
    slots.Free(big);
    try std.testing.expectEqual(0, slots.TrailingFreeLayers());
    slots.Free(medium);
    try std.testing.expectEqual(1, slots.TrailingFreeLayers());
    try std.testing.expectEqual(0, slots.Usage()[0].Pages);

    const whole = (try slots.Alloc(allocator, ClassOfSlot(4096))).?;
    try std.testing.expectEqual(0, AtlasHandle.Layer(whole));
    try std.testing.expectEqual(0, AtlasHandle.CellX(whole));
}

test "a full atlas asks for a layer, and the free layers at the end can be taken off" {
    var slots: AtlasSlots = .{};
    defer slots.Deinit(allocator);
    try slots.AddLayer(allocator);

    const first = (try slots.Alloc(allocator, ClassOfSlot(4096))).?;
    try std.testing.expectEqual(null, try slots.Alloc(allocator, ClassOfSlot(64)));
    try slots.AddLayer(allocator);
    const second = (try slots.Alloc(allocator, ClassOfSlot(64))).?;
    try std.testing.expectEqual(1, AtlasHandle.Layer(second));

    //only free layers at the end go, so handles never change
    slots.Free(first);
    try std.testing.expectEqual(0, slots.TrailingFreeLayers());
    slots.Free(second);
    try std.testing.expectEqual(2, slots.TrailingFreeLayers());
    slots.RemoveLayers(1);
    try std.testing.expectEqual(1, slots.LayerCount());
}

test "slots of every size handed out at random never overlap, and all come back when freed" {
    var slots: AtlasSlots = .{};
    defer slots.Deinit(allocator);
    for (0..3) |_| try slots.AddLayer(allocator);

    var prng = std.Random.DefaultPrng.init(0x5107);
    const random = prng.random();
    var handles: std.ArrayList(u32) = .empty;
    defer handles.deinit(allocator);

    for (0..2000) |_| {
        //mostly small, like a game's sprites and icons
        const class = @min(random.intRangeAtMost(u32, 0, 9), AtlasHandle.CLASS_COUNT - 1);
        if (try slots.Alloc(allocator, class)) |handle| try handles.append(allocator, handle);
        //free one now and then, so blocks split and merge as it goes
        if (handles.items.len > 0 and random.boolean()) slots.Free(handles.swapRemove(random.uintLessThan(usize, handles.items.len)));
    }
    try std.testing.expect(handles.items.len > 10);

    for (handles.items, 0..) |a, a_ind| {
        for (handles.items[a_ind + 1 ..]) |b| {
            if (AtlasHandle.Layer(a) != AtlasHandle.Layer(b)) continue;
            const a_size = AtlasHandle.SlotSize(AtlasHandle.Class(a)) / AtlasHandle.CELL;
            const b_size = AtlasHandle.SlotSize(AtlasHandle.Class(b)) / AtlasHandle.CELL;
            const apart_x = AtlasHandle.CellX(a) + a_size <= AtlasHandle.CellX(b) or AtlasHandle.CellX(b) + b_size <= AtlasHandle.CellX(a);
            const apart_y = AtlasHandle.CellY(a) + a_size <= AtlasHandle.CellY(b) or AtlasHandle.CellY(b) + b_size <= AtlasHandle.CellY(a);
            try std.testing.expect(apart_x or apart_y);
        }
        //a slot is always on its own size's grid, inside its layer
        const size = AtlasHandle.SlotSize(AtlasHandle.Class(a)) / AtlasHandle.CELL;
        try std.testing.expectEqual(0, AtlasHandle.CellX(a) % size);
        try std.testing.expectEqual(0, AtlasHandle.CellY(a) % size);
    }

    while (handles.pop()) |handle| slots.Free(handle);
    try std.testing.expectEqual(3, slots.TrailingFreeLayers());
    for (slots.Usage()) |class| try std.testing.expectEqual(0, class.Pages);
}
