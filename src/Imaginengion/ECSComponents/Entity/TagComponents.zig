const EngineContext = @import("../../Core/EngineContext.zig");

pub const StaticBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "StaticBodyTag";

    pub fn Deinit(_: *StaticBodyTag, _: *EngineContext) void {}
};

pub const DynamicBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "DynamicBodyTag";

    pub fn Deinit(_: *DynamicBodyTag, _: *EngineContext) void {}
};
