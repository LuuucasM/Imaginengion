//! PassPlan: which compute passes a render runs. No engine needed. Run with `zig build test`.
const std = @import("std");
const PassPlan = @import("../../Renderer/PassPlan.zig");

fn ExpectPlan(expected: PassPlan, actual: PassPlan) !void {
    try std.testing.expectEqualDeep(expected, actual);
}

test "both layers with shapes run both passes, the game under the overlay" {
    try ExpectPlan(.{ .Overlay = true, .Game = true, .OverlayOnGameBackground = false, .GameUnderOverlay = true, .ClearTo = .None }, PassPlan.Init(true, true, 5, 7));
}

test "an empty overlay skips its pass, and the game pass has nothing above it to read" {
    try ExpectPlan(.{ .Overlay = false, .Game = true, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .None }, PassPlan.Init(true, true, 0, 7));
}

test "an empty game layer skips its pass, and the overlay puts the game's background under what it drew" {
    try ExpectPlan(.{ .Overlay = true, .Game = false, .OverlayOnGameBackground = true, .GameUnderOverlay = false, .ClearTo = .None }, PassPlan.Init(true, true, 5, 0));
}

test "both empty runs no pass and clears to the game's background" {
    try ExpectPlan(.{ .Overlay = false, .Game = false, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .GameBackground }, PassPlan.Init(true, true, 0, 0));
}

test "an overlay-only render keeps a transparent background behind it" {
    //the editor's own UI: no game layer, so nothing is put behind the overlay, empty or not
    try ExpectPlan(.{ .Overlay = true, .Game = false, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .None }, PassPlan.Init(true, false, 5, 0));
    try ExpectPlan(.{ .Overlay = false, .Game = false, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .Transparent }, PassPlan.Init(true, false, 0, 0));
}

test "a game-only render ignores the overlay's shapes" {
    try ExpectPlan(.{ .Overlay = false, .Game = true, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .None }, PassPlan.Init(false, true, 5, 7));
    try ExpectPlan(.{ .Overlay = false, .Game = false, .OverlayOnGameBackground = false, .GameUnderOverlay = false, .ClearTo = .GameBackground }, PassPlan.Init(false, true, 5, 0));
}
