pub const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

// Re-export all GLFW functions and constants
pub usingnamespace c;
