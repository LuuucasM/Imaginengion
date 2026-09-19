const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;

// number of components the ECS provides itself (Parent, Child, SkipField, MainObject, EntityTag, ScriptTag)
// user components start at this index, so a user component's Ind is its list position + BuiltinComponentCount
pub const BuiltinComponentCount: usize = 6;

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
        pub const StaticSkipFieldT = StaticSkipField(components_len + BuiltinComponentCount);

        mSkipField: StaticSkipFieldT = .AllSkip,

        pub fn Deinit(_: *Self, _: *EngineContext) !void {}
    };
}

pub const MainObjectComponent = struct {
    pub const Ind: usize = 3;
    pub const Name: []const u8 = "MainObjectComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *MainObjectComponent, _: *EngineContext) !void {}
};

pub const EntityTagComponent = struct {
    pub const Ind: usize = 4;
    pub const Name: []const u8 = "EntityTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *EntityTagComponent, _: *EngineContext) !void {}
};

pub const ScriptTagComponent = struct {
    pub const Ind: usize = 5;
    pub const Name: []const u8 = "ScriptTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *ScriptTagComponent, _: *EngineContext) !void {}
};
