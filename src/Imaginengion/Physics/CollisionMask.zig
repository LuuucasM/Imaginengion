//! A set of collision layers, one bit per layer (named in CollisionLayers): which layers a collider is on, which it
//! collides with (CollisionFilter), which a physics query hits (PhysicsQueries.QueryOptions). Its own type rather than
//! a plain std.StaticBitSet so the editor can tell a set of layers from any other set of bits and show the layers'
//! names, on a script variable too. Saved as the bits' integer, {"mask": 5}, the way a plain bit set is
const std = @import("std");
const CollisionLayers = @import("CollisionLayers.zig");

const CollisionMask = @This();

pub const Bits = std.StaticBitSet(CollisionLayers.COUNT);

pub const empty: CollisionMask = .{ .mBits = .empty };
pub const full: CollisionMask = .{ .mBits = .full };

mBits: Bits = .empty,

/// The set with only `layer` in it
pub fn initOne(layer: usize) CollisionMask {
    var mask: CollisionMask = .empty;
    mask.set(layer);
    return mask;
}

pub fn isSet(self: CollisionMask, layer: usize) bool {
    return self.mBits.isSet(layer);
}

pub fn set(self: *CollisionMask, layer: usize) void {
    self.mBits.set(layer);
}

pub fn unset(self: *CollisionMask, layer: usize) void {
    self.mBits.unset(layer);
}

pub fn setValue(self: *CollisionMask, layer: usize, value: bool) void {
    self.mBits.setValue(layer, value);
}

/// Whether the two share a layer
pub fn intersects(self: CollisionMask, other: CollisionMask) bool {
    return self.mBits.intersectWith(other.mBits).findFirstSet() != null;
}

pub fn count(self: CollisionMask) usize {
    return self.mBits.count();
}

const Saved = struct { mask: Bits.MaskInt = 0 };

pub fn jsonStringify(self: *const CollisionMask, jw: anytype) !void {
    try jw.write(Saved{ .mask = self.mBits.mask });
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!CollisionMask {
    const saved = try std.json.innerParse(Saved, allocator, source, options);
    return .{ .mBits = .{ .mask = saved.mask } };
}
