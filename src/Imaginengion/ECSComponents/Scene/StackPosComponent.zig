const std = @import("std");
const StackPosComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

pub const Name: []const u8 = "StackPosComponent";

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent, _: *EngineContext) void {}
