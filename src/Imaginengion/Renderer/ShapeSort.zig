//! The order shapes go into the shape buffer. Each shape gets a key as it is added, and the buffer is uploaded sorted
//! by it, so whatever the GPU wants side by side is: direct shapes before marched ones, a combined SDF's shapes in one
//! run, and later shapes close in space close in the buffer for a BVH to be built over. Everything that points at a
//! place in the buffer (the direct/marched split, group ranges, BVH nodes) is worked out after the sort, from it.
const std = @import("std");

/// What a shape is sorted by. Compared as one number, so the top field decides the coarsest grouping and the bottom
/// one the finest. A field a feature doesn't use yet stays 0, which leaves the order to the fields that are set
pub const ShapeSortKey = packed struct(u64) {
    /// Direct shapes: their Morton code (their center's x, y and z bits interleaved), once there is a BVH to build
    /// over them. Marched shapes: where they come in their group's combining
    Order: u32 = 0,
    /// Marched shapes: which combined SDF they belong to, so each group is one run of the buffer. 0 for direct shapes
    Group: u31 = 0,
    /// How a ray finds it. The top bit, so every direct shape comes before every marched one
    Path: RayPath = .Direct,

    pub const RayPath = enum(u1) {
        /// found with a ray test straight against the shape
        Direct,
        /// found by stepping along the ray, for shapes that only have a distance function
        Marched,
    };

    pub fn Value(self: ShapeSortKey) u64 {
        return @bitCast(self);
    }
};

/// A shape's key and where it was added. Shapes with the same key keep the order they were added in, so the same
/// shapes always sort the same way, frame after frame
pub const SortEntry = struct {
    Key: ShapeSortKey,
    Index: u32,
};

fn LessThan(_: void, a: SortEntry, b: SortEntry) bool {
    const a_key = a.Key.Value();
    const b_key = b.Key.Value();
    if (a_key != b_key) return a_key < b_key;
    return a.Index < b.Index;
}

/// Puts entries in key order, ties in the order they were added
pub fn Sort(entries: []SortEntry) void {
    std.sort.pdq(SortEntry, entries, {}, LessThan);
}

/// `items` in the sorted entries' order, into `out`, which is as long as they are
pub fn Gather(comptime T: type, items: []const T, entries: []const SortEntry, out: []T) void {
    std.debug.assert(items.len == entries.len and out.len == entries.len);
    for (entries, out) |entry, *slot| slot.* = items[entry.Index];
}
