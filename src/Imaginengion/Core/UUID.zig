const std = @import("std");
pub fn GenUUID() !u128 {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    return rand.uintAtMost(u128, ~@as(u128, 0) - 1);
}
