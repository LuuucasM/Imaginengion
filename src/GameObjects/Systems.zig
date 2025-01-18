pub const RenderSystem = @import("Systems/RenderSystem.zig");

pub const SystemsList = [_]type{RenderSystem};

pub const ESystems = enum(usize) {
    RenderSystem = RenderSystem.Ind,
};
