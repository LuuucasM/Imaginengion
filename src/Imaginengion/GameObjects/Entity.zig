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
const RenderTargetComponent = Components.RenderTargetComponent;
const OutputFrameBuffer = @import("../Renderer/Renderer.zig").OutputFrameBuffer;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const PlayerSlotComponent = Components.PlayerSlotComponent;
const OnKeyPressedScript = Components.OnKeyPressedScript;
const ViewpointComponent = Components.ViewpointComponent;
const OnUpdateScript = Components.OnUpdateScript;
const PathType = @import("../Assets/AssetManager.zig").PathType;
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const EntityComponents = @import("Components.zig");
const Player = @import("../Players/Player.zig");
const SceneManager = @import("../Scene/SceneManager.zig");

pub const Iterator = struct {
    pub const IterType = enum {
        Child,
        Script,
    };
    _CurrentEntity: Entity,
    _FirstID: Type,
    _IsFirst: bool = true,

    pub fn next(self: *Iterator) ?Entity {
        if (self._IsFirst) {
            @branchHint(.cold);
            self._IsFirst = false;
        } else {
            if (self._CurrentEntity.mEntityID == self._FirstID) return null;
        }

        const entity = self._CurrentEntity;

        const entity_child_component = entity.GetComponent(EntityChildComponent).?;

        self._CurrentEntity = Entity{ .mEntityID = entity_child_component.mNext, .mSceneManager = entity.mSceneManager };

        return entity;
    }
};

pub const NewEntityConfig = struct {
    bAddUUID: bool = true,
    bAddName: bool = true,
    bAddTransform: bool = true,
};

pub const Type = u32;
pub const NullEntity: Type = std.math.maxInt(Type);
const Entity = @This();

mEntityID: Type = NullEntity,
mSceneManager: *SceneManager = undefined,

pub fn AddComponent(self: Entity, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
    const component_type = @TypeOf(new_component);
    _ValidateComponent(component_type);
    var comp = new_component;
    if (component_type == EntityComponents.QuadComponent) {
        comp.mTexture.mAssetManager = &engine_context.mAssetManager;
    }
    if (component_type == EntityComponents.TextComponent) {
        comp.mTextAssetHandle.mAssetManager = &engine_context.mAssetManager;
        comp.mTexHandle.mAssetManager = &engine_context.mAssetManager;
    }
    if (component_type == EntityComponents.AudioComponent) {
        comp.mAudioAsset.mAssetManager = &engine_context.mAssetManager;
    }
    return try self.mSceneManager.mECSManagerGO.AddComponent(engine_context.EngineAllocator(), self.mEntityID, comp);
}
pub fn RemoveComponent(self: Entity, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    try self.mSceneManager.mECSManagerGO.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}

pub fn GetComponent(self: Entity, comptime component_type: type) ?*component_type {
    return self.mSceneManager.mECSManagerGO.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mSceneManager.mECSManagerGO.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u64 {
    return self.mSceneManager.mECSManagerGO.GetComponent(UUIDComponent, self.mEntityID).?.*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return self.mSceneManager.mECSManagerGO.GetComponent(NameComponent, self.mEntityID).?.*.mName.items;
}

pub fn CreateChild(self: Entity, engine_context: *EngineContext, child_type: ChildType, config: NewEntityConfig) !Entity {
    const child_entity = Entity{ .mEntityID = try self.mSceneManager.mECSManagerGO.AddChild(engine_context.EngineAllocator(), self.mEntityID, child_type), .mSceneManager = self.mSceneManager };
    try child_entity.CreateEntityConfig(engine_context, config);
    return child_entity;
}

pub fn Duplicate(self: Entity) !Entity {
    return Entity{ .mEntityID = try self.mSceneManager.mECSManagerGO.DuplicateEntity(self.mEntityID), .mECSManagerRef = self.mECSManagerRef };
}
pub fn Delete(self: Entity, engine_context: *EngineContext) !void {
    try self.mSceneManager.mECSManagerGO.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}

pub fn GetViewpointComponent(self: Entity) ?ViewpointComponent {
    if (self.GetComponent(ViewpointComponent)) |comp| return comp;

    if (self.GetIterator(.Child)) |iter| {
        while (iter.Next()) |child_entity| {
            if (child_entity.GetComponent(ViewpointComponent)) |comp| return comp;
        }
    }
    return null;
}

pub fn GetIterator(self: Entity, comptime iter_type: Iterator.IterType) ?Iterator {
    if (self.GetComponent(EntityParentComponent)) |parent_component| {
        const first = switch (iter_type) {
            .Child => parent_component.mFirstEntity,
            .Script => parent_component.mFirstScript,
        };
        if (first == NullEntity) return null;
        return Iterator{
            ._CurrentEntity = Entity{ .mEntityID = first, .mSceneManager = self.mSceneManager },
            ._FirstID = first,
        };
    } else {
        return null;
    }
}

pub fn AddComponentScript(self: Entity, engine_context: *EngineContext, rel_path_script: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(
        engine_context,
        .{ .File = .{ .rel_path = rel_path_script, .path_type = path_type } },
    );
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    std.debug.assert(script_asset.GetScriptType() == .EntityInputPressed or script_asset.GetScriptType() == .EntityOnUpdate);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try self.CreateChild(engine_context, .Script, .{ .bAddName = false, .bAddTransform = false, .bAddUUID = false });

    _ = try new_script_entity.AddComponent(engine_context, new_script_component);

    // Add the appropriate script type component based on the script asset
    switch (script_asset.GetScriptType()) {
        .EntityInputPressed => {
            _ = try new_script_entity.AddComponent(engine_context, OnKeyPressedScript{});
        },
        .EntityOnUpdate => {
            _ = try new_script_entity.AddComponent(engine_context, OnUpdateScript{});
        },
        else => @panic("this shouldnt happen!\n"),
    }
}

pub fn AddRenderTarget(self: Player, engine_context: *EngineContext) !*RenderTargetComponent {
    var new_render_comp = RenderTargetComponent{};
    const engine_allocator = engine_context.EngineAllocator();

    new_render_comp.mFrameBuffer.Init(engine_context, 1600, 900);

    return try self.AddComponent(engine_allocator, new_render_comp);
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

pub fn CreateEntityConfig(self: Entity, engine_context: *EngineContext, config: NewEntityConfig) !void {
    if (config.bAddUUID) {
        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = engine_context.GenUUID() });
        try self.mSceneManager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
    }
    if (config.bAddName) {
        var new_name_component = NameComponent{ .mAllocator = engine_context.EngineAllocator() };
        _ = try new_name_component.mName.print(new_name_component.mAllocator, "New Entity", .{});
        _ = try self.AddComponent(engine_context, new_name_component);
    }
    if (config.bAddTransform) {
        _ = try self.AddComponent(engine_context, TransformComponent{});
    }
}

pub fn IsActive(self: Entity) bool {
    return self.IsValid() and self.mSceneManager.mECSManagerGO.IsActiveEntity(self.mEntityID);
}

pub fn Invalidate(self: *Entity) void {
    self.mEntityID = NullEntity;
}

pub fn IsValid(self: Entity) bool {
    return if (self.mEntityID != NullEntity) true else false;
}

fn _ValidateComponent(component_type: type) void {
    comptime var is_valid = false;
    inline for (EntityComponents.ComponentsList) |list_type| {
        if (component_type == list_type) {
            is_valid = true;
        }
    }

    if (!is_valid) {
        @compileError(@typeName(component_type) ++ "Type is not a valid entity component");
    }
}
