const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const InputCodes = @import("InputCodes.zig").InputCodes;
const CircularBuffer = @import("../Core/CircularBuffer.zig").CircularBuffer;

pub const InputPress = struct {
    mInputCode: InputCodes,
    mTimestamp: i32,
};

var StaticInputContext: InputContext = InputContext{};

pub const InputContext = struct {
    _InputPressedSet: HashMap(InputCodes, u1) = undefined,
    _MousePositionNew: Vec2f32 = Vec2f32{ 0.0, 0.0 },
    _MouseScrolledNew: Vec2f32 = Vec2f32{ 0.0, 0.0 },
    _MousePositionOld: Vec2f32 = Vec2f32{ 0.0, 0.0 },
    _MouseScrolledOld: Vec2f32 = Vec2f32{ 0.0, 0.0 },
    _MousePositionDelta: Vec2f32 = Vec2f32{ 0.0, 0.0 },
    _MouseScrolledDelta: Vec2f32 = Vec2f32{ 0.0, 0.0 },

    pub fn IsKeyPressed(self: *InputContext, key: InputCodes) bool {
        return self._InputPressedSet.contains(key);
    }
    pub fn IsMouseButtonPressed(self: *InputContext, button: InputCodes) bool {
        return self._InputPressedSet.contains(button);
    }
    pub fn GetMousePosition(self: *InputContext) Vec2f32 {
        return self._MousePositionNew;
    }
    pub fn GetMousePositionDelta(self: *InputContext) Vec2f32 {
        return self._MousePositionDelta;
    }
    pub fn GetMouseScrolled(self: *InputContext) Vec2f32 {
        return self._MouseScrolledNew;
    }
    pub fn GetMouseScrolledDelta(self: *InputContext) Vec2f32 {
        return self._MouseScrolledDelta;
    }
};

var InputGPA = std.heap.DebugAllocator(.{}).init;

pub fn Init() !void {
    StaticInputContext._InputPressedSet = HashMap(InputCodes, u1).init(InputGPA.allocator());
}
pub fn Deinit() void {
    StaticInputContext._InputPressedSet.deinit();
    _ = InputGPA.deinit();
}

pub fn GetInstance() *InputContext {
    return &StaticInputContext;
}

pub fn OnUpdate() void {
    StaticInputContext._MousePositionDelta = StaticInputContext._MousePositionNew - StaticInputContext._MousePositionOld;
    StaticInputContext._MouseScrolledDelta = StaticInputContext._MouseScrolledNew - StaticInputContext._MouseScrolledOld;
    StaticInputContext._MousePositionOld = StaticInputContext._MousePositionNew;
    StaticInputContext._MouseScrolledOld = StaticInputContext._MouseScrolledNew;
}

pub fn SetInputPressed(input: InputCodes) !void {
    if (StaticInputContext._InputPressedSet.contains(input) == true) {
        try StaticInputContext._InputPressedSet.put(input, 1);
    } else {
        try StaticInputContext._InputPressedSet.put(input, 0);
        StaticInputContext._InputPressBuffer.Push(.{ .mInputCode = input, .mTimestamp = @intCast(std.time.milliTimestamp()) });
    }
}

pub fn SetInputReleased(input: InputCodes) void {
    _ = StaticInputContext._InputPressedSet.remove(input);
}
pub fn IsInputPressed(input: InputCodes) bool {
    return StaticInputContext._InputPressedSet.contains(input);
}
pub fn SetMousePosition(new_pos: Vec2f32) void {
    StaticInputContext._MousePosition = new_pos;
}
pub fn GetMousePosition() Vec2f32 {
    return StaticInputContext._MousePosition;
}
pub fn SetMouseScrolled(new_scrolled: Vec2f32) void {
    StaticInputContext._MouseScrolled = new_scrolled;
}
pub fn GetMouseScrolled() Vec2f32 {
    return StaticInputContext._MouseScrolled;
}
