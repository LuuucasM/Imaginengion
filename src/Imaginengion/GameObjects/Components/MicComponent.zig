const BUFFER_CAPACITY = @import("../../AudioManager/AudioManager.zig").BUFFER_CAPACITY;
const SPSCRingBuffer = @import("../../Core/SPSCRingBuffer.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const MicComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;

mAudioBuffer: SPSCRingBuffer(f32, BUFFER_CAPACITY) = SPSCRingBuffer(f32, BUFFER_CAPACITY).Init(),

pub fn Deinit(_: *MicComponent) void {}

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
