//Standalone tests (no engine needed). Every test file lives under Tests/, mirroring the source folder it
//covers. A file listed directly in build.zig is its own module root and can't @import("../..."), so this
//index sits at the source root and pulls them in. Engine-dependent tests are indexed in Imaginengion.zig.
test {
    _ = @import("Tests/Core/SkipFieldTests.zig");
    _ = @import("Tests/Core/SparseSetTests.zig");
    _ = @import("Tests/Core/SPSCRingBufferTests.zig");
    _ = @import("Tests/Math/AudioTests.zig");
    _ = @import("Tests/Math/MathTypesTests.zig");
    _ = @import("Tests/Math/CameraRayTests.zig");
    _ = @import("Tests/Math/RayIntersectTests.zig");
    _ = @import("Tests/Math/ScreenRectTests.zig");
    _ = @import("Tests/Math/OverlayCanvasTests.zig");
    _ = @import("Tests/Renderer/TextLayoutTests.zig");
    _ = @import("Tests/Inputs/InputTests.zig");
    _ = @import("Tests/UI/LayoutTests.zig");
    _ = @import("Tests/UI/TextEditTests.zig");
}
