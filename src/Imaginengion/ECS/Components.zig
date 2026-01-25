const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ParentComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 0;
        pub const Editable: bool = false;
        pub const Name: []const u8 = "ParentComponent";

        mFirstEntity: entity_t = std.math.maxInt(entity_t),
        mFirstScript: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}

pub fn ChildComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Editable: bool = false;
        pub const Ind: usize = 1;
        pub const Name: []const u8 = "ChildComponent";

        mFirst: entity_t = std.math.maxInt(entity_t),
        mPrev: entity_t = std.math.maxInt(entity_t),
        mNext: entity_t = std.math.maxInt(entity_t),
        mParent: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}
