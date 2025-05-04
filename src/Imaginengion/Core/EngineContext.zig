const StaticInputContext = @import("../Inputs/Input.zig");
const InputContext = @import("../Inputs/Input.zig").InputContext;

var _StaticEngineContext: EngineContext = EngineContext{};

pub const EngineContext = extern struct {
    _StaticInputContext: *InputContext = undefined,
    _DeltaTime: f32 = 0,
    pub fn GetDeltaTime(self: *EngineContext) f32 {
        return self._DeltaTime;
    }
    pub fn GetInputContext(self: *EngineContext) *InputContext {
        return self._StaticInputContext;
    }
};

pub fn Init() void {
    _StaticEngineContext._StaticInputContext = StaticInputContext.GetInstance();
}

pub fn GetInstance() *EngineContext {
    return &_StaticEngineContext;
}

pub fn SetDT(delta_time: f32) void {
    _StaticEngineContext._DeltaTime = delta_time;
}
