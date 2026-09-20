const Entity = @import("../../ECSObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const PossessComponent = @This();

pub const Name: []const u8 = "PossessComponent";

mPossessedEntity: Entity = .uninit,

pub fn Deinit(_: *PossessComponent, _: *EngineContext) void {}
