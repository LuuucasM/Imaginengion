const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;

// number of components the ECS provides itself (Parent, Child, SkipField, MainObject, EntityTag, ScriptTag)
// user components start at this index, so a user component's Ind is its list position + BuiltinComponentCount
pub const BuiltinComponentCount: usize = 6;

/// A component's slot in a given manager's component list: its position in that list,
/// offset past the builtins. The list is passed explicitly so one shared component type
/// (UUIDComponent, NameComponent, ...) can sit at a different position in each manager.
pub fn ListInd(comptime components_list: []const type, comptime component_type: type) u16 {
    for (components_list, 0..) |list_type, i| {
        if (list_type == component_type) return @intCast(i + BuiltinComponentCount);
    }
    @compileError(@typeName(component_type) ++ " is not in the given components list");
}

pub fn ParentComponent(entity_t: type) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 0;
        pub const Name: []const u8 = "ParentComponent";

        mFirstEntity: entity_t = std.math.maxInt(entity_t),
        mFirstScript: entity_t = std.math.maxInt(entity_t),

        pub fn Deinit(_: *Self, _: *EngineContext) void {}
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

        pub fn Deinit(_: *Self, _: *EngineContext) void {}
    };
}

pub fn SkipFieldComponent(comptime components_len: comptime_int) type {
    return struct {
        const Self = @This();

        pub const Ind: usize = 2;
        pub const Name: []const u8 = "SkipFieldComponent";
        pub const TrackFreeIDs: bool = true; // destroyed entity ids are recycled through this component's sparse set
        pub const StaticSkipFieldT = StaticSkipField(components_len + BuiltinComponentCount);

        mSkipField: StaticSkipFieldT = .AllSkip,

        pub fn Deinit(_: *Self, _: *EngineContext) void {}
    };
}

pub const MainObjectComponent = struct {
    pub const Ind: usize = 3;
    pub const Name: []const u8 = "MainObjectComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *MainObjectComponent, _: *EngineContext) void {}
};

pub const EntityTagComponent = struct {
    pub const Ind: usize = 4;
    pub const Name: []const u8 = "EntityTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *EntityTagComponent, _: *EngineContext) void {}
};

pub const ScriptTagComponent = struct {
    pub const Ind: usize = 5;
    pub const Name: []const u8 = "ScriptTagComponent";

    mBit: u1 = 0,

    pub fn Deinit(_: *ScriptTagComponent, _: *EngineContext) void {}
};
