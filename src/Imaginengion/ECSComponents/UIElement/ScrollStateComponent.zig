const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;

const ScrollStateComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "ScrollStateComponent";

/// How a scrolling element (ScrollComponent) is scrolled right now. Given to every element that gets a ScrollComponent,
/// worked out while it runs and never saved or copied: a scene always opens scrolled to the start

/// How far its entity's children are scrolled, x to the right and y down. Kept in range by layout
mOffset: Vec2(f32) = .{ .x = 0, .y = 0 },
/// How much room the children take, as of the last layout
mContentSize: Vec2(f32) = .{ .x = 0, .y = 0 },
/// Its scrollbars' thumbs, children of its entity made by the scroll system while the children overflow it
mThumbX: ?Entity = null,
mThumbY: ?Entity = null,

pub fn Deinit(_: *ScrollStateComponent, _: *EngineContext) void {}
