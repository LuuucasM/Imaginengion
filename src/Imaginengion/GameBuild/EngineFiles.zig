//! The engine's own files a game uses: the ones the engine opens by itself with nothing naming them, and what building a
//! game copies. Only constants, with no imports: the build reads this file too, and so does the engine.

pub const ASSETS_PATH = "src/Imaginengion/EngineAssets";

pub const DEFAULT_THEME = ASSETS_PATH ++ "/themes/Default.imtheme";
pub const PLAIN_TEXTURE = ASSETS_PATH ++ "/textures/White.png";
pub const DEFAULT_TEXTURE = ASSETS_PATH ++ "/textures/DefaultTexture.png";
pub const DEFAULT_FONT = ASSETS_PATH ++ "/fonts/default/static/ChironGoRoundTC-Regular.ttf";
pub const DEFAULT_SOUND = ASSETS_PATH ++ "/sounds/DefaultSound.mp3";

/// What every game needs whatever is in it: the UI's theme and plain texture, and what an asset falls back on
pub const ALWAYS_NEEDED = [_][]const u8{
    DEFAULT_THEME,
    PLAIN_TEXTURE,
    DEFAULT_TEXTURE,
    DEFAULT_FONT,
    DEFAULT_SOUND,
};

/// What building a game copies, from ASSETS_PATH. Fixed for now: nothing yet looks at what a game uses
pub const COPIED_ASSETS = [_][]const u8{
    "fonts/default/static/ChironGoRoundTC-Bold.json",
    "fonts/default/static/ChironGoRoundTC-Bold.png",
    "fonts/default/static/ChironGoRoundTC-Bold.ttf",
    "fonts/default/static/ChironGoRoundTC-Regular.json",
    "fonts/default/static/ChironGoRoundTC-Regular.png",
    "fonts/default/static/ChironGoRoundTC-Regular.ttf",
    "sounds/DefaultSound.mp3",
    "textures/DefaultTexture.png",
    "textures/White.png",
    "themes/Default.imtheme",
};

/// The stock UI scripts, from ASSETS_PATH. Building a game copies the folder and builds every script in it
pub const STOCK_SCRIPTS_FOLDER = "scripts/UI";
