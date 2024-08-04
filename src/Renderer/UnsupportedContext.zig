const UnsupportedContext = @This();

pub fn Init(self: UnsupportedContext) void {
    _ = self;
    Unsupported();
}

pub fn SwapBuffers(self: UnsupportedContext) void {
    _ = self;
    Unsupported();
}

fn Unsupported(self: UnsupportedContext) noreturn {
    _ = self;
    @compileError("Unsupported OS for RenderContext");
}
