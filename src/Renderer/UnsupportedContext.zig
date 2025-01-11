const UnsupportedContext = @This();

pub fn Init() UnsupportedContext {
    Unsupported();
}

pub fn SwapBuffers(self: UnsupportedContext) void {
    _ = self;
    Unsupported();
}

pub fn GetMaxTextureImageSlots() u32 {
    FreeUnsupported();
}

fn Unsupported(self: UnsupportedContext) noreturn {
    _ = self;
    @compileError("Unsupported OS for RenderContext");
}

fn FreeUnsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}
