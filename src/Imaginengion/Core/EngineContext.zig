const InputManager = @import("../Inputs/Input.zig");

var EngineContext: Engine = Engine{};

pub const Engine = struct {
    pub fn Init() void {}
    pub fn GetInputManager(self: Engine) *InputManager {
        return InputManager.GetInstance();
    }
};

pub fn Init() void {}

pub fn GetInstance() *Engine {
    return &EngineContext;
}

pub fn GetInputManager() *InputManager {
    _ = self;
    return InputManager.GetInstance();
}
