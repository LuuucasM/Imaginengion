const std = @import("std");
pub fn GenUUID() !u64 {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    return rand.uintAtMost(u64, ~@as(u64, 0) - 1);
}
