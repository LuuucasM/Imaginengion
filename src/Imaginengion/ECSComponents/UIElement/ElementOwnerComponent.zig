const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ElementOwnerComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "ElementOwnerComponent";

/// The entity a UI element is the UI of: the one whose UIElementComponent points at it. Set by the UIManager whenever
/// an entity takes an element (UIManager.Adopt), never saved. An element whose owner is gone, or no longer points back
/// at it, is deleted at the end of the frame
mOwner: Entity = .uninit,

pub fn Deinit(_: *ElementOwnerComponent, _: *EngineContext) void {}
