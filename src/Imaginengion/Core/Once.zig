const std = @import("std");

pub fn once(comptime f: fn () void) Once(f) {
    return Once(f){};
}

pub fn Once(comptime f: fn () void) type {
    return struct {
        mDone: bool = false,
        pub fn call(self: *@This()) void {
            if (self.mDone) {
                return;
            } else {
                @branchHint(.cold);
                f();
            }
        }
    };
}
