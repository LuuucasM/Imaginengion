//Standalone tests (no engine needed) whose code imports across folders. A test file listed directly in
//build.zig is its own module root, so it can't @import("../..."); pulling it in from here, at the
//source root, lets it. Tests that only import their own folder can stay listed in build.zig on their own.
test {
    _ = @import("Renderer/TextLayoutTests.zig");
}
