const std = @import("std");
const ComponentManager = @This();

pub fn Init(self: ComponentManager) void {
    _ = self;
}

pub fn Deinit(self: ComponentManager) void {
    _ = self;
}

pub fn RegisterComponent(self: ComponentManager, comptime ComponentType: type) void {
    _ = self;
    _ = ComponentType;
}

pub fn AddComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128, component: ComponentType) *ComponentType {
    _ = self;
    _ = entityID;
    _ = component;
}

pub fn AddComponents(self: ComponentManager, comptime ComponentTypes: anytype, entityID: u128, components: anytype) std.meta.Tuple(ComponentTypes) {
    _ = self;
    _ = entityID;
    _ = components;
}

pub fn RemoveComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128) void {
    _ = self;
    _ = ComponentType;
    _ = entityID;
}

pub fn RemoveComponents(self: ComponentManager, comptime ComponentTypes: anytype, entityID: u128) void {
    _ = self;
    _ = ComponentTypes;
    _ = entityID;
}

pub fn HasComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128) bool {
    _ = self;
    _ = ComponentType;
    _ = entityID;
}
