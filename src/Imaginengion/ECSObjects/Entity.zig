const std = @import("std");
const Components = @import("../ECSComponents/EComponents.zig");
const UUIDComponent = Components.UUIDComponent;
const EntitySceneComponent = Components.EntitySceneComponent;
const NameComponent = Components.NameComponent;
const ScriptComponent = Components.ScriptComponent;
const TransformComponent = Components.TransformComponent;
const TransformDirtyTag = Components.TransformDirtyTag;
const RigidBodyComponent = Components.RigidBodyComponent;
const AudioComponent = Components.AudioComponent;
const StaticBodyTag = Components.StaticBodyTag;
const DynamicBodyTag = Components.DynamicBodyTag;
const KinematicBodyTag = Components.KinematicBodyTag;
const LayoutDirtyTag = Components.LayoutDirtyTag;
const LayoutSystem = @import("../UI/LayoutSystem.zig");
const GameLayerTag = Components.GameLayerTag;
const OverlayLayerTag = Components.OverlayLayerTag;
const LayerType = @import("../ECSComponents/Shared/TagComponents.zig").LayerType;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const RenderTargetComponent = Components.RenderTargetComponent;
const OnKeyPressedScript = Components.OnKeyPressedScript;
const ViewpointComponent = Components.ViewpointComponent;
const OnUpdateScript = Components.OnUpdateScript;
const OnCollisionBeginScript = Components.OnCollisionBeginScript;
const MainObjectComponent = @import("../ECS/Components.zig").MainObjectComponent;
const PathType = @import("../ECSManagers/AManager.zig").PathType;
const ScriptAsset = @import("../ECSComponents/AComponents.zig").ScriptAsset;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const Player = @import("Player.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const AssetHandle = @import("AssetHandle.zig");
const Voice = @import("Voice.zig");
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

/// Nothing added, for objects whose components all come from somewhere else (e.g. a file)
pub const BlankConfig: CreateConfig = .{
    .bAddUUID = false,
    .bAddName = false,
    .bAddTransform = false,
};

/// A script child (see Core.AddScript): no UUID, nothing looks one up and it is saved as its ScriptComponent alone
pub const ScriptConfig: CreateConfig = .{
    .bAddUUID = false,
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
pub const SetName = Core.SetName;

pub fn CreateChild(self: Entity, engine_context: *EngineContext, child_type: ChildType, config: CreateConfig) !Entity {
    const child_entity = try Core.CreateChild(self, engine_context, child_type, config);
    //a child entity belongs to the same scene as its parent, so it is in the same layer too
    _ = try child_entity.AddComponent(engine_context, self.GetComponent(EntitySceneComponent).?.*);
    switch (self.GetLayer()) {
        .GameLayer => _ = try child_entity.AddComponent(engine_context, GameLayerTag{}),
        .OverlayLayer => _ = try child_entity.AddComponent(engine_context, OverlayLayerTag{}),
    }
    return child_entity;
}

/// The layer this entity is drawn in, from the layer tag it took from its scene (see GameLayerTag)
pub fn GetLayer(self: Entity) LayerType {
    if (self.HasComponent(OverlayLayerTag)) return .OverlayLayer;
    std.debug.assert(self.HasComponent(GameLayerTag));
    return .GameLayer;
}

pub const Duplicate = Core.Duplicate;

pub const Delete = Core.Delete;

pub const SetTmpl = Core.SetTmpl;

pub const Fill = Core.Fill;

pub const Strip = Core.Strip;

pub const MakeTmpl = Core.MakeTmpl;

pub fn GetViewpointComponent(self: Entity) ?*ViewpointComponent {
    const viewpoint_entity = self.GetViewpointEntity() orelse return null;
    return viewpoint_entity.GetComponent(ViewpointComponent);
}

/// The entity that actually holds this game object's viewpoint: itself, or a convenience child.
/// Anything that needs the camera's transform should read it from here rather than from self.
pub fn GetViewpointEntity(self: Entity) ?Entity {
    if (self.HasComponent(ViewpointComponent)) return self;

    //the viewpoint may live on a convenience child instead of on the game object itself.
    //a child that is its own MainObject is a nested game object, so its viewpoint is not ours.
    var iter = self.GetIterator(.Child);
    while (iter.next()) |child_entity| {
        if (child_entity.HasComponent(MainObjectComponent)) continue;
        if (child_entity.HasComponent(ViewpointComponent)) return child_entity;
    }
    return null;
}

/// The game object this entity is part of: itself if it is a MainObject, otherwise the nearest ancestor
/// that is, otherwise the root of its hierarchy. What a click on one of its shapes should select, since
/// a shape may sit on a convenience child (a button's label) rather than on the object itself.
pub fn GetMainObject(self: Entity) Entity {
    var current = self;
    while (!current.HasComponent(MainObjectComponent)) {
        const child_component = current.GetComponent(EntityChildComponent) orelse return current;
        current = Entity{ .mID = child_component.mParent, .mManager = self.mManager };
    }
    return current;
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
        .EntityOnCollisionBegin => {
            _ = try new_script_entity.AddComponent(engine_context, OnCollisionBeginScript{});
        },
        .EntityOnCollisionEnd => {
            _ = try new_script_entity.AddComponent(engine_context, Components.OnCollisionEndScript{});
        },
        .EntityOnPreSolve => {
            _ = try new_script_entity.AddComponent(engine_context, Components.OnPreSolveScript{});
        },
        .EntityOnPhysicsUpdate => {
            _ = try new_script_entity.AddComponent(engine_context, Components.OnPhysicsUpdateScript{});
        },
        .EntityOnPointerEvent => {
            _ = try new_script_entity.AddComponent(engine_context, Components.OnPointerEventScript{});
        },
        .EntityOnUIEvent => {
            _ = try new_script_entity.AddComponent(engine_context, Components.OnUIEventScript{});
        },
        else => @panic("this shouldnt happen!\n"),
    }
}

/// The only supported way to write an entity's local transform. Each one tags the entity so the
/// next UpdateWorldTransforms pass picks it up; that is why TransformComponent's local fields are
/// private. An entity with no TransformComponent is a no-op, matching GetComponent returning null.
/// Plays this entity's AudioComponent from the start. Keep the returned voice to stop that one sound later, or ignore it
/// for a one-shot. Null (and logged) when nothing could play, e.g. the entity has no AudioComponent
pub fn PlayAudio(self: Entity, engine_context: *EngineContext) !?Voice {
    return try engine_context.mAudioManager.PlayVoice(engine_context, self);
}

/// Stops every attached voice this entity's AudioComponent is playing. Detached one-shots play on, stop one of those
/// with the Voice that PlayAudio returned
pub fn StopAudio(self: Entity) void {
    if (self.GetComponent(AudioComponent)) |audio_component| audio_component.StopVoices();
}

pub fn SetTranslation(self: Entity, engine_context: *EngineContext, translation: Vec3(f32)) !void {
    const transform = self.GetComponent(TransformComponent) orelse return;
    transform._SetLocalUntagged(translation, transform.GetRotation(), transform.GetScale());
    try self.MarkTransformDirty(engine_context);
    try self._SnapBackIfPlacedByLayout(engine_context);
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
    try self._SnapBackIfPlacedByLayout(engine_context);
}

/// Layout owns the x and y of what it places, so a translation set by hand on one is put back by the next layout
/// pass, every time, rather than sticking until something unrelated relays the tree out. Z is never layout's
fn _SnapBackIfPlacedByLayout(self: Entity, engine_context: *EngineContext) !void {
    if (LayoutSystem.IsPlacedByLayout(self)) try self.MarkLayoutDirty(engine_context);
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

/// Asks for the layout tree this entity is in to be worked out again (UI/LayoutSystem.zig). Tagging any entity of a
/// tree relays out the whole tree, once. Adding the tag twice would trip AddComponent's assert, so this is the only
/// way it goes on
pub fn MarkLayoutDirty(self: Entity, engine_context: *EngineContext) !void {
    if (self.HasComponent(LayoutDirtyTag)) return;
    _ = try self.AddComponent(engine_context, LayoutDirtyTag{});
}

/// Removed synchronously, like ClearTransformDirty: a change after the layout pass then tags again instead of being
/// swallowed by a tag still waiting for the end of the frame
pub fn ClearLayoutDirty(self: Entity, engine_context: *EngineContext) !void {
    if (!self.HasComponent(LayoutDirtyTag)) return;
    try self.RemoveComponentSync(engine_context, LayoutDirtyTag);
}

/// The tags a rigid body carries exactly one of. The tag is the record of the body's type: changing the
/// type is adding the new tag, which takes the others off (see OnBodyTypeTagAdded)
pub const BodyTypeTags = [_]type{ StaticBodyTag, KinematicBodyTag, DynamicBodyTag };

/// Brings a rigid body in step with its type tag. One with no tag yet gets one: static if it was given no
/// mass, which is how a body was made static before there were body types, and dynamic otherwise. Then its
/// mass is kept at RigidBodyComponent.MIN_MASS or above, and the inverse mass the solver divides by is
/// worked out, 0 unless it is dynamic. A static body also loses any velocity it was given, it never moves.
///
/// Runs whenever a rigid body or a type tag is added (Manager.AddComponent) and after the mass is edited in
/// the components panel, so every way a body comes into being goes through it: code, a file, a template.
/// An entity with a type tag and no rigid body is left alone, it is a tag loaded ahead of its rigid body.
//anyerror: it adds a type tag, whose add hook calls back in here, so the error set can not be inferred
pub fn SyncRigidBody(self: Entity, engine_context: *EngineContext) anyerror!void {
    const rigid_body = self.GetComponent(RigidBodyComponent) orelse return;

    if (!self.HasBodyTypeTag()) {
        //adding the tag comes back through here (OnBodyTypeTagAdded), which does the rest
        if (rigid_body._Mass > 0.0) {
            _ = try self.AddComponent(engine_context, DynamicBodyTag{});
        } else {
            _ = try self.AddComponent(engine_context, StaticBodyTag{});
        }
        return;
    }

    rigid_body._Mass = @max(rigid_body._Mass, RigidBodyComponent.MIN_MASS);
    rigid_body._InvMass = if (self.HasComponent(DynamicBodyTag)) 1.0 / rigid_body._Mass else 0.0;

    if (self.HasComponent(StaticBodyTag)) {
        rigid_body._Velocity = std.mem.zeroes(Vec3(f32));
        rigid_body._Force = std.mem.zeroes(Vec3(f32));
    }
}

/// Called by Manager.AddComponent for any of BodyTypeTags. The new tag replaces whichever type the body
/// had. The removals are synchronous on purpose: a deferred one would leave two type tags on the entity until
/// end of frame, and a physics step before then would find the body in two type queries at once.
pub fn OnBodyTypeTagAdded(self: Entity, engine_context: *EngineContext, comptime added_tag: type) !void {
    inline for (BodyTypeTags) |tag_type| {
        if (tag_type != added_tag and self.HasComponent(tag_type)) try self.RemoveComponentSync(engine_context, tag_type);
    }
    try self.SyncRigidBody(engine_context);
}

/// Makes a rigid body the type of the given tag (one of BodyTypeTags). The way to change a type from code:
/// adding the tag directly works as well, but not when the body already has it, the same as adding any
/// component an entity already carries
pub fn SetBodyType(self: Entity, engine_context: *EngineContext, comptime body_type_tag: type) !void {
    if (self.HasComponent(body_type_tag)) return;
    _ = try self.AddComponent(engine_context, body_type_tag{});
}

/// Sets a rigid body's mass, kept at RigidBodyComponent.MIN_MASS or above, and the inverse mass with it.
/// The way to change a mass from code. Does nothing on an entity with no rigid body
pub fn SetMass(self: Entity, engine_context: *EngineContext, mass: f32) !void {
    const rigid_body = self.GetComponent(RigidBodyComponent) orelse return;
    //clamped here as well: a mass of 0 or less reads as static to a body that has no type tag yet
    rigid_body._Mass = @max(mass, RigidBodyComponent.MIN_MASS);
    try self.SyncRigidBody(engine_context);
}

pub fn HasBodyTypeTag(self: Entity) bool {
    inline for (BodyTypeTags) |tag_type| {
        if (self.HasComponent(tag_type)) return true;
    }
    return false;
}

/// Takes the body type tag off, for when the RigidBodyComponent is going away. SyncRigidBody can not do it
/// on the removal path, because RemoveComponent only queues and the component is still readable when it
/// returns.
pub fn ClearBodyTags(self: Entity, engine_context: *EngineContext) !void {
    inline for (BodyTypeTags) |tag_type| {
        if (self.HasComponent(tag_type)) try self.RemoveComponentSync(engine_context, tag_type);
    }
}

pub fn _CalculateWorldTransform(self: Entity) void {
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
                //order: the position so far is an offset in this parent's space, so it is scaled and
                //turned by the parent before the parent's own translation is added; rotations multiply
                //parent-first; scales multiply. Applying every ancestor's local transform in turn,
                //nearest first, gives the same answer that pass gets from the parent's cached world
                //transform.
                translation_out = parent_transform.GetTranslation().AddVec(translation_out.MulVec(parent_transform.GetScale()).QuatRotate(parent_transform.GetRotation()));
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
    std.debug.assert(script_type == .EntityInputPressed or script_type == .EntityOnUpdate or script_type == .EntityOnCollisionBegin or script_type == .EntityOnCollisionEnd or script_type == .EntityOnPreSolve or script_type == .EntityOnPhysicsUpdate or script_type == .EntityOnPointerEvent or script_type == .EntityOnUIEvent);
}
