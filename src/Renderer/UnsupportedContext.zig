const UnsupportedContext = @This();

pub fn Init() UnsupportedContext {
    Unsupported();
}

pub fn SwapBuffers(self: UnsupportedContext) void {
    _ = self;
    Unsupported();
}

pub fn GetMaxTextureImageSlots(self: UnsupportedContext) u32 {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}
