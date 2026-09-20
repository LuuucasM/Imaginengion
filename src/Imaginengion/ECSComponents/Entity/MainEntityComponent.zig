const EngineContext = @import("../../Core/EngineContext.zig");

const MainEntityComp = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "MainEntityComponent";

pub fn Deinit(_: *MainEntityComp, _: *EngineContext) void {}
