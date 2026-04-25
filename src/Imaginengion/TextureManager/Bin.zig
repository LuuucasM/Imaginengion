pub fn Bin(comptime atlas_size: usize, comptime slot_size: usize, comptime padding: usize) type {
    return struct {
        pub const SlotSize = slot_size;
        pub const MaxTextureSize = slot_size - (2 * padding);
        pub const SlotsPerRow = atlas_size / slot_size;
        pub const TotalSlots = SlotsPerRow * SlotsPerRow;
    };
}
