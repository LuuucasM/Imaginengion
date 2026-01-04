const BUFFER_CAPACITY = @import("../../AudioManager/AudioManager.zig").BUFFER_CAPACITY;
const SPSCRingBuffer = @import("../../Core/SPSCRingBuffer.zig");
const tAudioBuffer = @import("../../AudioManager/AudioManager.zig").tAudioBuffer;
const ComponentsList = @import("../Components.zig").ComponentsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const MicComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = false;

mAudioBuffer: tAudioBuffer = tAudioBuffer.Init(),

pub fn Deinit(_: *MicComponent, _: *EngineContext) !void {}

pub fn GetName(_: MicComponent) []const u8 {
    return "MicComponent";
}

pub fn GetInd(_: MicComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == MicComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
