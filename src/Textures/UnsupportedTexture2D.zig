pub fn GetWidth(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn GetHeight(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn GetID(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn SetData(self: Texture, data: *anyopaque) void {
    _ = self;
    _ = data;
    Unsupported();
}
pub fn Bind(self: Texture) void {
    _ = self;
    Unsupported();
}
pub fn Unbind(self: Texture) void {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in Texture2D\n");
}
