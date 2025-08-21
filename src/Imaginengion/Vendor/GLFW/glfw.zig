pub const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

// Access via `glfw.c.*` or re-export selectively elsewhere.
