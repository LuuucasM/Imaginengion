const std = @import("std");
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Components = @import("Components.zig");
const UUIDComponent = Components.UUIDComponent;
const EntitySceneComponent = Components.EntitySceneComponent;
const NameComponent = Components.NameComponent;
const ScriptComponent = Components.ScriptComponent;
const TransformComponent = Components.TransformComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const PlayerSlotComponent = Components.PlayerSlotComponent;
const OnInputPressedScript = Components.OnInputPressedScript;
const OnUpdateScript = Components.OnUpdateScript;
const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const EntityComponents = @import("Components.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Player = @import("../Players/Player.zig");
const SceneManager = @import("../Scene/SceneManager.zig");

pub const NewEntityConfig = struct {
    bAddUUID: bool,
    bAddName: bool,
    bAddTransform: bool,
};

pub const EntityRef = struct {
    mUUID: u64,
    mEntity: Entity,

    pub fn GetEntity(self: *EntityRef) ?Entity {
        if (self.mEntity.mEntityID != NullEntity) {
            return self.mEntity;
        } else {
            if (self.mEntity.mSceneManager.GetEntityByUUID(self.mUUID)) |entity| {
                self.mEntity = entity;
                return entity;
            }
        }
    }
};

pub const Type = u32;
pub const NullEntity: Type = std.math.maxInt(Type);
const Entity = @This();

mEntityID: Type = NullEntity,
mSceneManager: *SceneManager = undefined,

pub fn AddComponent(self: Entity, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mSceneManager.mECSManagerGO.AddComponent(self.mEntityID, new_component);
}
pub fn RemoveComponent(self: Entity, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    self.mSceneManager.mECSManagerGO.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}

pub fn GetComponent(self: Entity, comptime component_type: type) ?*component_type {
    return self.mSceneManager.mECSManagerGO.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mSceneManager.mECSManagerGO.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mSceneManager.mECSManagerGO.GetComponent(UUIDComponent, self.mEntityID).?.*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return self.mSceneManager.mECSManagerGO.GetComponent(NameComponent, self.mEntityID).?.*.mName.items;
}

pub fn Duplicate(self: Entity) !Entity {
    return Entity{ .mEntityID = try self.mSceneManager.mECSManagerGO.DuplicateEntity(self.mEntityID), .mECSManagerRef = self.mECSManagerRef };
}
pub fn Delete(self: Entity, engine_context: *EngineContext) !void {
    try self.mSceneManager.mECSManagerGO.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}

pub fn Possess(self: Entity, player: Player) void {
    if (self.GetComponent(PlayerSlotComponent)) |player_slot_component| {
        player_slot_component.mPlayerEntity = player;
    }
}

pub fn AddComponentScript(self: *Entity, engine_context: *EngineContext, rel_path_script: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), rel_path_script, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    std.debug.assert(script_asset.mScriptType == .EntityInputPressed or script_asset.mScriptType == .EntityOnUpdate);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try self.AddChild(engine_context.EngineAllocator(), .Script);

    _ = try new_script_entity.AddComponent(new_script_component);

    // Add the appropriate script type component based on the script asset
    switch (script_asset.mScriptType) {
        .EntityInputPressed => {
            _ = try new_script_entity.AddComponent(OnInputPressedScript{});
        },
        .EntityOnUpdate => {
            _ = try new_script_entity.AddComponent(OnUpdateScript{});
        },
        else => @panic("this shouldnt happen!\n"),
    }
}

pub fn _CalculateWorldTransform(self: Entity) void {
    const zone = Tracy.ZoneInit("Entity::_CalculateWorldTransform", @src());
    defer zone.Deinit();

    if (self.GetComponent(TransformComponent)) |transform| {
        var translation_out = transform.Translation;
        var rotation_out = transform.Rotation;
        var scale_out = transform.Scale;

        var child_component = self.GetComponent(EntityChildComponent);

        while (child_component != null) {
            const parent_entity = Entity{ .mEntityID = child_component.?.mParent, .mECSManagerRef = self.mECSManagerRef };

            if (parent_entity.GetComponent(TransformComponent)) |parent_transform| {
                translation_out += parent_transform.Translation;
                rotation_out = LinAlg.QuatMulQuat(rotation_out, parent_transform.Rotation);
                scale_out += parent_transform.Scale;
            }

            child_component = parent_entity.GetComponent(EntityChildComponent);
        }

        transform._InternalData.WorldPosition = translation_out;
        transform._InternalData.WorldRotation = rotation_out;
        transform._InternalData.WorldScale = scale_out;
    }
}

pub fn CreateEntityConfig(self: Entity, engine_allocator: std.mem.Allocator, config: NewEntityConfig) !void {
    if (config.bAddUUID) {
        const new_uuid_component = UUIDComponent{ .ID = GenUUID() };
        _ = try self.AddComponent(new_uuid_component);
        self.mSceneManager.mEntityUUIDToWorldID.put(new_uuid_component.ID);
    }
    if (config.bAddName) {
        const new_name_component = NameComponent{ .mAllocator = engine_allocator };
        _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("New Entity");
        self.AddComponent(new_name_component);
    }
    if (config.bAddTransform) {
        _ = try self.AddComponent(TransformComponent{});
    }
}
