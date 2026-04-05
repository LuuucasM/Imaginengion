const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;

pub fn ParentComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 0;
        pub const Name: []const u8 = "ParentComponent";

        mFirstEntity: entity_t = std.math.maxInt(entity_t),
        mFirstScript: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}

pub fn ChildComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 1;
        pub const Name: []const u8 = "ChildComponent";

        mFirst: entity_t = std.math.maxInt(entity_t),
        mPrev: entity_t = std.math.maxInt(entity_t),
        mNext: entity_t = std.math.maxInt(entity_t),
        mParent: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}

pub fn SkipFieldComponent(comptime components_len: comptime_int) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 2;
        pub const Name: []const u8 = "SkipFieldComponent";
        pub const StaticSkipFieldT = StaticSkipField(components_len + 5); // +5 because 0 is parent component, 1 is child component, and 2 is skip field component, entity tag, script tag

        mSkipField: StaticSkipFieldT = .AllSkip,

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}

pub const EntityTagComponent = struct {
    pub const Ind: usize = 3;
    pub const Name: []const u8 = "EntityTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *EntityTagComponent, _: *EngineContext) !void {}
};

pub const ScriptTagComponent = struct {
    pub const Ind: usize = 4;
    pub const Name: []const u8 = "ScriptTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *ScriptTagComponent, _: *EngineContext) !void {}
};
