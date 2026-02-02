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

pub const Type = u32;
pub const NullEntity: Type = std.math.maxInt(Type);
const Entity = @This();

mEntityID: Type = NullEntity,
mECSManagerRef: *ECSManagerGameObj = undefined,

pub fn AddComponent(self: Entity, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mECSManagerRef.AddComponent(self.mEntityID, new_component);
}
pub fn RemoveComponent(self: Entity, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    self.mECSManagerRef.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}
pub fn AddBlankChild(self: Entity, child_type: ChildType) !Entity {
    const new_child = Entity{ .mEntityID = try self.mECSManagerRef.AddChild(self.mEntityID, child_type), .mECSManagerRef = self.mECSManagerRef };
    _ = try new_child.AddComponent(self.GetComponent(EntitySceneComponent).?.*);
    return new_child;
}
pub fn AddChild(self: Entity, engine_allocator: std.mem.Allocator, child_type: ChildType) !Entity {
    const new_child = Entity{ .mEntityID = try self.mECSManagerRef.AddChild(self.mEntityID, child_type), .mECSManagerRef = self.mECSManagerRef };
    _ = try new_child.AddComponent(UUIDComponent{ .ID = try GenUUID() });
    _ = try new_child.AddComponent(self.GetComponent(EntitySceneComponent).?.*);
    const new_name_component = try new_child.AddComponent(NameComponent{ .mAllocator = engine_allocator });
    _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("New Entity");
    if (child_type == .Entity) _ = try new_child.AddComponent(TransformComponent{});
    return new_child;
}
pub fn GetComponent(self: Entity, comptime component_type: type) ?*component_type {
    return self.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mECSManagerRef.GetComponent(UUIDComponent, self.mEntityID).?.*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return self.mECSManagerRef.GetComponent(NameComponent, self.mEntityID).?.*.mName.items;
}

pub fn Duplicate(self: Entity) !Entity {
    return Entity{ .mEntityID = try self.mECSManagerRef.DuplicateEntity(self.mEntityID), .mECSManagerRef = self.mECSManagerRef };
}
pub fn Delete(self: Entity, engine_context: *EngineContext) !void {
    try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DestroyEntityEvent = .{ .mEntity = self } });
    try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DeleteEntityEvent = .{ .mEntity = self } });
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

pub fn AddComponentUUID(self: *Entity, engine_context: *EngineContext) !void {
    const uuid_component = try self.AddComponent(UUIDComponent{ .ID = GenUUID() });
    engine_context.mSceneSerializer.mEntityUUIDToWorldID.put(engine_context.EngineAllocator(), uuid_component.ID);
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
