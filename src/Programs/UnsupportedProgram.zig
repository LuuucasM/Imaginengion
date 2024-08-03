const UnsupportedProgram = @This();

pub fn Init(self: UnsupportedProgram) void {
    _ = self;
    Unsupported();
}

pub fn Deinit(self: UnsupportedProgram) void {
    _ = self;
    Unsupported();
}

pub fn OnUpdate(self: UnsupportedProgram) void {
    _ = self;
    Unsupported();
}

pub fn OnEvent(self: UnsupportedProgram) void {
    _ = self;
    Unsupported();
}

fn Unsupported(self: UnsupportedProgram) noreturn {
    _ = self;
    @compileError("Unsupported Program Option in Program");
}
