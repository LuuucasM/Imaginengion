const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;

const UnsupportedProgram = @This();

pub fn Init(self: UnsupportedProgram) !void {
    _ = self;
    Unsupported();
}

pub fn Deinit(self: UnsupportedProgram) !void {
    _ = self;
    Unsupported();
}

pub fn OnUpdate(self: *UnsupportedProgram, dt: f64) !void {
    _ = self;
    _ = dt;
    Unsupported();
}

pub fn OnWindowResize(_: *UnsupportedProgram, _: WindowResizeEvent) !bool {
    Unsupported();
}

pub fn OnInputPressedEvent(self: *UnsupportedProgram, e: InputPressedEvent) bool {
    _ = self;
    _ = e;
    Unsupported();
}

pub fn OnImguiEvent(self: *UnsupportedProgram, event: *ImguiEvent) void {
    _ = self;
    _ = event;
    Unsupported();
}

pub fn OnGameEvent(self: *UnsupportedProgram, event: *GameEvent) void {
    _ = self;
    _ = event;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported Program Option in Program");
}
