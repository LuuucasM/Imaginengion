const std = @import("std");
const Components = @import("../ECSComponents/EComponents.zig");
const UUIDComponent = Components.UUIDComponent;
const EntitySceneComponent = Components.EntitySceneComponent;
const NameComponent = Components.NameComponent;
const ScriptComponent = Components.ScriptComponent;
const TransformComponent = Components.TransformComponent;
const TransformDirtyTag = Components.TransformDirtyTag;
const RigidBodyComponent = Components.RigidBodyComponent;
const StaticBodyTag = Components.StaticBodyTag;
const DynamicBodyTag = Components.DynamicBodyTag;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const RenderTargetComponent = Components.RenderTargetComponent;
const OnKeyPressedScript = Components.OnKeyPressedScript;
const ViewpointComponent = Components.ViewpointComponent;
const OnUpdateScript = Components.OnUpdateScript;
const MainObjectComponent = @import("../ECS/Components.zig").MainObjectComponent;
const PathType = @import("../ECSManagers/AManager.zig").PathType;
const ScriptAsset = @import("../ECSComponents/AComponents.zig").ScriptAsset;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const Player = @import("Player.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const AssetHandle = @import("AssetHandle.zig");
const ECSCore = @import("ECSObject.zig").Core;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const Core = ECSCore(Entity);

pub const Iterator = Core.Iterator;

pub const CreateConfig = struct {
    bAddUUID: bool,
    bAddName: bool,
    bAddTransform: bool,
};

pub const DefaultConfig: CreateConfig = .{
    .bAddUUID = true,
    .bAddName = true,
    .bAddTransform = true,
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
pub const RemoveComponentSync = Core.RemoveComponentSync;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetUUID = Core.GetUUID;

pub const GetName = Core.GetName;

pub fn CreateChild(self: Entity, engine_context: *EngineContext, child_type: ChildType, config: CreateConfig) !Entity {
    const child_entity = try Core.CreateChild(self, engine_context, child_type, config);
    //a child entity belongs to the same scene as its parent
    _ = try child_entity.AddComponent(engine_context, self.GetComponent(EntitySceneComponent).?.*);
    return child_entity;
}

pub const Duplicate = Core.Duplicate;

pub const Delete = Core.Delete;

pub fn GetViewpointComponent(self: Entity) ?*ViewpointComponent {
    if (self.GetComponent(ViewpointComponent)) |comp| return comp;

    //the viewpoint may live on a convenience child instead of on the game object itself.
    //a child that is its own MainObject is a nested game object, so its viewpoint is not ours.
    var iter = self.GetIterator(.Child);
    while (iter.next()) |child_entity| {
        if (child_entity.HasComponent(MainObjectComponent)) continue;
        if (child_entity.GetComponent(ViewpointComponent)) |comp| return comp;
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

/// The only supported way to write an entity's local transform. Each one tags the entity so the
/// next UpdateWorldTransforms pass picks it up; that is why TransformComponent's local fields are
/// private. An entity with no TransformComponent is a no-op, matching GetComponent returning null.
pub fn SetTranslation(self: Entity, engine_context: *EngineContext, translation: Vec3(f32)) !void {
    const transform = self.GetComponent(TransformComponent) orelse return;
    transform._SetLocalUntagged(translation, transform.GetRotation(), transform.GetScale());
    try self.MarkTransformDirty(engine_context);
}

pub fn SetRotation(self: Entity, engine_context: *EngineContext, rotation: Quat(f32)) !void {
    const transform = self.GetComponent(TransformComponent) orelse return;
    transform._SetLocalUntagged(transform.GetTranslation(), rotation, transform.GetScale());
    try self.MarkTransformDirty(engine_context);
}

pub fn SetScale(self: Entity, engine_context: *EngineContext, scale: Vec3(f32)) !void {
    const transform = self.GetComponent(TransformComponent) orelse return;
    transform._SetLocalUntagged(transform.GetTranslation(), transform.GetRotation(), scale);
    try self.MarkTransformDirty(engine_context);
}

/// Writes all three at once, tagging only once. Prefer this over three separate setters when a
/// caller changes more than one part of the transform.
pub fn SetTransform(self: Entity, engine_context: *EngineContext, translation: Vec3(f32), rotation: Quat(f32), scale: Vec3(f32)) !void {
    const transform = self.GetComponent(TransformComponent) orelse return;
    transform._SetLocalUntagged(translation, rotation, scale);
    try self.MarkTransformDirty(engine_context);
}

/// Adding the tag twice would trip AddComponent's assert, so this is the only way it goes on.
pub fn MarkTransformDirty(self: Entity, engine_context: *EngineContext) !void {
    if (self.HasComponent(TransformDirtyTag)) return;
    _ = try self.AddComponent(engine_context, TransformDirtyTag{});
}

/// Removed synchronously, not queued. A deferred removal would leave the tag readable for the
/// rest of the frame, so every later transform pass in that frame would walk this entity's subtree
/// again and MarkTransformDirty would see the tag still present and skip re-tagging a genuinely
/// new change. The tag is zero-sized, so applying the removal now moves no component storage and
/// invalidates no pointer.
pub fn ClearTransformDirty(self: Entity, engine_context: *EngineContext) !void {
    if (!self.HasComponent(TransformDirtyTag)) return;
    try self.RemoveComponentSync(engine_context, TransformDirtyTag);
}

/// Brings StaticBodyTag/DynamicBodyTag back in step with the body's inverse mass. Exactly one of
/// them is present while the entity has a RigidBodyComponent, and neither once it does not, so
/// CollisionManager.BroadPass can treat "carries DynamicBodyTag" as the whole answer to whether an
/// entity can be moved by the solver.
///
/// Call this after anything that changes _InvMass. The removals are synchronous on purpose: a
/// deferred one would leave both tags on the entity until end of frame, and a broad pass running
/// before then would find it in the dynamic set and the static set at once.
pub fn SyncBodyTags(self: Entity, engine_context: *EngineContext) !void {
    const rigid_body = self.GetComponent(RigidBodyComponent) orelse {
        try self.ClearBodyTags(engine_context);
        return;
    };

    if (rigid_body._InvMass != 0.0) {
        if (self.HasComponent(StaticBodyTag)) try self.RemoveComponentSync(engine_context, StaticBodyTag);
        if (!self.HasComponent(DynamicBodyTag)) _ = try self.AddComponent(engine_context, DynamicBodyTag{});
    } else {
        if (self.HasComponent(DynamicBodyTag)) try self.RemoveComponentSync(engine_context, DynamicBodyTag);
        if (!self.HasComponent(StaticBodyTag)) _ = try self.AddComponent(engine_context, StaticBodyTag{});
    }
}

/// Takes both body tags off, for when the RigidBodyComponent is going away. SyncBodyTags cannot do
/// this itself on the removal path, because RemoveComponent only queues and the component is still
/// readable when it returns.
pub fn ClearBodyTags(self: Entity, engine_context: *EngineContext) !void {
    if (self.HasComponent(StaticBodyTag)) try self.RemoveComponentSync(engine_context, StaticBodyTag);
    if (self.HasComponent(DynamicBodyTag)) try self.RemoveComponentSync(engine_context, DynamicBodyTag);
}

pub fn _CalculateWorldTransform(self: Entity) void {
    const zone = Tracy.ZoneInit("Entity::_CalculateWorldTransform", @src());
    defer zone.Deinit();

    if (self.GetComponent(TransformComponent)) |transform| {
        var translation_out = transform.GetTranslation();
        var rotation_out = transform.GetRotation();
        var scale_out = transform.GetScale();

        var child_component = self.GetComponent(EntityChildComponent);

        //walk all the way to the root. an ancestor without a TransformComponent (a convenience
        //entity that only carries a bundle of components) contributes nothing, but it never stops
        //the walk: the whole chain still has to propagate through it.
        while (child_component != null) {
            const parent_entity = Entity{ .mID = child_component.?.mParent, .mManager = self.mManager };

            if (parent_entity.GetComponent(TransformComponent)) |parent_transform| {
                //the same three rules PhysicsManager.CalculateEntityTransform uses, in the same
                //order: translations add, rotations multiply parent-first, scales multiply.
                //Composing every ancestor's local transform here gives the same answer that pass
                //gets from the parent's cached world transform.
                translation_out = translation_out.AddVec(parent_transform.GetTranslation());
                rotation_out = parent_transform.GetRotation().MulQuat(rotation_out);
                scale_out = scale_out.MulVec(parent_transform.GetScale());
            }

            child_component = parent_entity.GetComponent(EntityChildComponent);
        }

        transform._InternalData.WorldPosition = translation_out;
        transform._InternalData.WorldRotation = rotation_out;
        transform._InternalData.WorldScale = scale_out;
    }
}

pub fn CreateEntityConfig(self: Entity, engine_context: *EngineContext, config: CreateConfig) !void {
    if (config.bAddUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const new_random = io_source.interface();
        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = new_random.int(u64) });
        try self.mManager.mEManager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mID);
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

pub const AddComponentScript = Core.AddComponentScript;

pub const IsActive = Core.IsActive;

pub const Invalidate = Core.Invalidate;

pub const IsIDValid = Core.IsIDValid;

fn _ValidateScriptType(script_type: ScriptAsset.ScriptType) void {
    std.debug.assert(script_type == .EntityInputPressed or script_type == .EntityOnUpdate);
}
