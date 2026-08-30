const std = @import("std");
const Components = @import("../ECSComponents/EComponents.zig");
const UUIDComponent = Components.UUIDComponent;
const EntitySceneComponent = Components.EntitySceneComponent;
const NameComponent = Components.NameComponent;
const ScriptComponent = Components.ScriptComponent;
const TransformComponent = Components.TransformComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const RenderTargetComponent = Components.RenderTargetComponent;
const OnKeyPressedScript = Components.OnKeyPressedScript;
const ViewpointComponent = Components.ViewpointComponent;
const OnUpdateScript = Components.OnUpdateScript;
const MainEntityComponent = Components.MainEntityComponent;
const PathType = @import("../Assets/AssetManager.zig").PathType;
const ScriptAsset = @import("../ECSComponents/AComponents.zig").ScriptAsset;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const Player = @import("Player.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const AssetHandle = @import("AssetHandle.zig");
const ECSCore = @import("ECSObject.zig").Core;
const WorldManager = @import("../Core/WorldManager.zig");

const Core = ECSCore(Entity);

pub const Iterator = Core.Iterator;

pub const NewEntityConfig = struct {
    bAddUUID: bool = false,
    bAddName: bool = false,
    bAddTransform: bool = false,
};

pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);
const Entity = @This();

pub const uninit: Entity = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *WorldManager,

pub const AddComponent = Core.AddComponent;

pub const RemoveComponent = Core.RemoveComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetUUID = Core.GetUUID;

pub const GetName = Core.GetName;

pub fn CreateChild(self: Entity, engine_context: *EngineContext, child_type: ChildType, config: NewEntityConfig) !Entity {
    const child_entity = try Core.CreateChild(self, engine_context, child_type);
    try child_entity.CreateEntityConfig(engine_context, config);
    _ = try child_entity.AddComponent(engine_context, self.GetComponent(EntitySceneComponent).?.*);
    @compileLog("TODO to change to move functionality of NewEntityConfig to the EManager instead of on the entity directly");
    return child_entity;
}

pub const Duplicate = Core.Duplicate;

pub const Delete = Core.Delete;

pub fn GetViewpointComponent(self: Entity) ?ViewpointComponent {
    if (self.GetComponent(ViewpointComponent)) |comp| return comp;

    if (self.GetIterator(.Child)) |iter| {
        while (iter.Next()) |child_entity| {
            if (child_entity.GetComponent(ViewpointComponent)) |comp| return comp;
        }
    }
    return null;
}

pub const GetIterator = Core.GetIterator;

pub fn AddScript(self: Entity, engine_context: *EngineContext, new_script_handle: AssetHandle) !void {
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);
    const script_type = script_asset.GetScriptType();
    _ValidateScriptType(script_type);

    const new_script_entity = try Core.AddScript(self, engine_context, new_script_handle);

    // Add the appropriate script type component based on the script asset
    switch (script_type) {
        .EntityInputPressed => {
            _ = try new_script_entity.AddComponent(engine_context, OnKeyPressedScript{});
        },
        .EntityOnUpdate => {
            _ = try new_script_entity.AddComponent(engine_context, OnUpdateScript{});
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
            const parent_entity = Entity{ .mEntityID = child_component.?.mParent, .mSceneManager = self.mSceneManager };

            if (parent_entity.GetComponent(TransformComponent)) |parent_transform| {
                translation_out = translation_out.AddVec(parent_transform.Translation);
                rotation_out = rotation_out.MulQuat(parent_transform.Rotation);
                scale_out = scale_out.AddVec(parent_transform.Scale);
            }

            if (parent_entity.HasComponent(MainEntityComponent)) break;

            child_component = parent_entity.GetComponent(EntityChildComponent);
        }

        transform._InternalData.WorldPosition = translation_out;
        transform._InternalData.WorldRotation = rotation_out;
        transform._InternalData.WorldScale = scale_out;
    }
}

pub fn CreateEntityConfig(self: Entity, engine_context: *EngineContext, config: NewEntityConfig) !void {
    if (config.bAddUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const new_random = io_source.interface();
        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = new_random.int(u64) });
        try self.mSceneManager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
    }
    if (config.bAddName) {
        var new_name_component: NameComponent = .empty;
        _ = try new_name_component.mName.print(engine_context.EngineAllocator(), "New Entity", .{});
        _ = try self.AddComponent(engine_context, new_name_component);
    }
    if (config.bAddTransform) {
        _ = try self.AddComponent(engine_context, TransformComponent{});
    }
}

pub const IsActive = Core.IsActive;

pub const Invalidate = Core.Invalidate;

pub const IsIDValid = Core.IsIDValid;

fn _ValidateScriptType(script_type: ScriptAsset.ScriptType) void {
    std.debug.assert(script_type == .EntityInputPressed or script_type == .EntityOnUpdate);
}
