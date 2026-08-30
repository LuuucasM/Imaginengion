const WorldManager = @This();

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

pub fn GetEntity(self: *WorldManager, entity_id: Entity.Type) Entity {
    return Entity{ .mID = entity_id, .mManager = self };
}

pub fn GetGameContext(self: *WorldManager, gamecontext_id: GameContext.Type) GameContext {
    return GameContext{ .mID = gamecontext_id, .mManager = self };
}

pub fn GetPlayer(self: *WorldManager, player_id: Player.Type) Player {
    return Player{ .mID = player_id, .mManager = self };
}

pub fn GetScene(self: *WorldManager, scene_id: Scene.Type) Scene {
    return Scene{ .mID = scene_id, .mManager = self };
}
