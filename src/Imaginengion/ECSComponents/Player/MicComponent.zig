const std = @import("std");
const BUFFER_CAPACITY = @import("../../AudioManager/AudioManager.zig").BUFFER_CAPACITY;
const TAudioBuffer = @import("../../AudioManager/AudioManager.zig").TAudioBuffer;
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const MicComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "MicComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == MicComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mAudioBuffer: TAudioBuffer = .default,

pub fn Deinit(_: *MicComponent, _: *EngineContext) !void {}

//nothing is saved yet
const Json = JsonUtils.JsonFields(MicComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
