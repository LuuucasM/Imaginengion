const std = @import("std");
const Audio3D = @This();

pub const AudioEmission = extern struct {
    buffer: *anyopaque,
    offset: u32,
    volume: f32,
    pitch: f32,
    looping: bool,
};

pub const Emissions3D = std.ArrayList(AudioEmission);

pub fn Init(_: Audio3D) void {}

pub fn Deinit(_: Audio3D) void {}
