const EngineContext = @import("../../Core/EngineContext.zig");
const Player = @import("../../ECSObjects/Player.zig");

const ViewportComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "ViewportComponent";

/// On an entity with a quad shape (ShapeComponent): the quad shows what a player's camera sees, the player's render target
/// (RenderTargetComponent), instead of its texture. The editor's viewport, a split screen view, a security camera's
/// monitor in a game. The quad's size sets the size the player renders at, so the view is never stretched
/// (Renderer/Viewports.zig). Not saved yet: the editor makes its viewports in code
/// The player whose view it shows
mPlayer: Player = .uninit,

pub fn Deinit(_: *ViewportComponent, _: *EngineContext) void {}
