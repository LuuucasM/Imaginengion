const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;

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

pub fn SkipFieldComponent(comptime components_types: []const type) type {
    return struct {
        const Self = @This();

        pub const Editable: bool = false;
        pub const Ind: usize = 2;
        pub const Name: []const u8 = "SkipFieldComponent";
        pub const StaticSkipFieldT = StaticSkipField(components_types.len + 3);
        mSkipField: StaticSkipFieldT = StaticSkipFieldT.Init(.AllSkip), // +3 because 0 is parent component, 1 is child component, and 2 is skip field component

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}
