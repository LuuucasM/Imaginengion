//! The engine's own files a game uses: the ones the engine opens by itself with nothing naming them, and where its stock
//! scripts are. Only constants, with no imports: the build reads this file too, and so does the engine.

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

/// The stock UI scripts, from ASSETS_PATH (Widgets.StockScript)
pub const STOCK_SCRIPTS_FOLDER = "scripts/UI";
