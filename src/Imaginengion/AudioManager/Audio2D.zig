const std = @import("std");
const Audio2D = @This();

pub const AudioEmission = extern struct {
    buffer: *anyopaque,
    offset: u32,
    volume: f32,
    pitch: f32,
    looping: bool,
};

pub const Emissions2D = std.ArrayList(AudioEmission);

pub fn Init(_: Audio2D) void {}

pub fn Deinit(_: Audio2D) void {}
