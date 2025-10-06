const std = @import("std");
const ComponentCategory = @import("ECSManager.zig").ComponentCategory;

pub fn ParentComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Category: ComponentCategory = .Unique;
        pub const Editable: bool = false;

        mFirstChild: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self) !void {}

        pub fn GetName(_: Self) []const u8 {
            return "ParentComponent";
        }

        pub fn GetInd(self: Self) u32 {
            _ = self;
            return @intCast(Ind);
        }

        pub const Ind: usize = 0;
    };
}

pub fn ChildComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Category: ComponentCategory = .Unique;
        pub const Editable: bool = false;

        mFirst: entity_t = std.math.maxInt(entity_t),
        mPrev: entity_t = std.math.maxInt(entity_t),
        mNext: entity_t = std.math.maxInt(entity_t),
        mParent: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self) !void {}

        pub fn GetName(self: Self) []const u8 {
            _ = self;
            return "ChildComponent";
        }

        pub fn GetInd(self: Self) u32 {
            _ = self;
            return @intCast(Ind);
        }

        pub const Ind: usize = 1;
    };
}
