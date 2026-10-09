//! Which of a render's two compute passes run. The overlay pass writes every pixel first, then the game pass draws
//! under it, so skipping an empty layer means telling the other pass what it would have done: the game pass then has no
//! overlay to read, and the overlay pass puts the game's background under what it drew. With both empty neither pass
//! runs and the texture is only cleared.
const PassPlan = @This();

pub const Clear = enum {
    /// a pass runs and writes every pixel
    None,
    /// nothing is drawn behind the overlay layer either (a render of the overlay only)
    Transparent,
    GameBackground,
};

Overlay: bool,
Game: bool,
/// The overlay pass puts the game's background under what it drew: the game layer is drawn but has nothing in it, so
/// its pass doesn't run
OverlayOnGameBackground: bool,
/// The game pass draws under what the overlay pass wrote, so it reads the texture first
GameUnderOverlay: bool,
/// What the texture is cleared to when neither pass runs
ClearTo: Clear,

/// From whether the render draws each layer at all and how many shapes each has
pub fn Init(draws_overlay: bool, draws_game: bool, overlay_count: u32, game_count: u32) PassPlan {
    const overlay = draws_overlay and overlay_count > 0;
    const game = draws_game and game_count > 0;
    return .{
        .Overlay = overlay,
        .Game = game,
        .OverlayOnGameBackground = overlay and draws_game and !game,
        .GameUnderOverlay = overlay and game,
        .ClearTo = if (overlay or game) .None else if (draws_game) .GameBackground else .Transparent,
    };
}

/// Which compile of a pass's shader runs it (build_shaders.zig, SDFRayMarcher.Features)
pub const ShaderVariant = enum {
    /// everything the marcher can do
    Full,
    /// only direct shapes and their masks, with merges and marching compiled out: fewer registers, so more pixels in
    /// flight at once
    Lean,
};

/// The leanest compile that can draw a pass: Lean unless it has a merge, or a shape found by marching (every shape past
/// the first `direct_count`)
pub fn VariantFor(merge_count: usize, shape_count: usize, direct_count: usize) ShaderVariant {
    return if (merge_count == 0 and direct_count == shape_count) .Lean else .Full;
}
