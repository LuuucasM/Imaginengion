const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const ObjectRefComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "ObjectRefComponent";

/// Which object an entity stands for, e.g. a row of a hierarchy panel: a drag source (DragSourceComponent) with one
/// carries the object, and a drop target that takes ObjectRefComponent reads which object was dropped. Set up by code,
/// never saved
mObject: Ref,

/// Any of the four object types. The same cases as the editor's selection (EditorProgram.SelectedObject)
pub const Ref = union(enum) {
    entity: Entity,
    scene_layer: Scene,
    player: Player,
    gamecontext: GameContext,

    pub fn Of(object: anytype) Ref {
        return switch (@TypeOf(object)) {
            Entity => .{ .entity = object },
            Scene => .{ .scene_layer = object },
            Player => .{ .player = object },
            GameContext => .{ .gamecontext = object },
            else => @compileError("Not an object type: " ++ @typeName(@TypeOf(object))),
        };
    }
};

pub fn Deinit(_: *ObjectRefComponent, _: *EngineContext) void {}
