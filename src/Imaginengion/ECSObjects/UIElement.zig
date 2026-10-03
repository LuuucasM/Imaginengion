const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const UIManager = @import("../UI/UIManager.zig");
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const ElementOwnerComponent = UIComponents.ElementOwnerComponent;
const Entity = @import("Entity.zig");
const ECSCore = @import("ECSObject.zig").Core;
const UIElement = @This();

/// The UI side of an entity that has UI: where its UI-only components live (UIComponents.zig), in the UIManager's ECS
/// rather than on the entity. The entity reaches it through its UIElementComponent and the element points back at the
/// entity (ElementOwnerComponent), the way an AudioComponent and its voices know each other. Like a Voice it points at
/// its (engine level) manager directly, since elements for every world live in the one UIManager
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(UIElement);

pub const uninit: UIElement = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *UIManager,

/// The entity this is the UI of. uninit for an element no entity has taken yet
pub fn GetOwner(self: UIElement) Entity {
    return self.GetComponent(ElementOwnerComponent).?.mOwner;
}

/// Deletes the element at the end of the frame
pub fn Delete(self: UIElement, engine_context: *EngineContext) !void {
    try self.mManager.DeleteElement(engine_context, self);
}

pub const AddComponent = Core.AddComponent;
pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;
pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const IsActive = Core.IsActive;
pub const IsIDValid = Core.IsIDValid;
pub const Invalidate = Core.Invalidate;
