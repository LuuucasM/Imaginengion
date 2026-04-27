const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("../Scene/SceneManager.zig").ECSManagerPlayer;
pub const NullPlayer: Type = std.math.maxInt(Type);
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const PlayerComponents = @import("Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerNameComponent = PlayerComponents.NameComponent;
const UUIDComponent = PlayerComponents.UUIDComponent;
const PlayerMic = PlayerComponents.MicComponent;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const RenderTargetComponent = PlayerComponents.RenderTargetComponent;
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const PlayerParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const PlayerChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const GenUUID = @import("../Serializer/Serializer.zig").GenUUID;
const PathType = @import("../Assets/Assets/FileMetaData.zig").PathType;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const ScriptComponent = PlayerComponents.ScriptComponent;
const Player = @This();

pub const Iterator = struct {
    pub const IterType = enum {
        Child,
        Script,
    };
    _CurrentPlayer: Player,
    _FirstID: Type,
    _IsFirst: bool = true,

    pub fn next(self: *Iterator) ?Player {
        if (self._IsFirst) {
            @branchHint(.cold);
            self._IsFirst = false;
        } else {
            if (self._CurrentPlayer.mEntityID == self._FirstID) return null;
        }

        const player = self._CurrentPlayer;

        const player_child_component = player.GetComponent(PlayerChildComponent).?;

        self._CurrentPlayer = Player{ .mEntityID = player_child_component.mNext, .mScenemanager = player.mScenemanager };

        return player;
    }
};

pub const NewPlayerConfig = struct {
    bAddNameComponent: bool = true,
    bAddUUIDComponent: bool = true,
    bAddPossessComponent: bool = true,
    bAddMicComponent: bool = true,
    bAddRenderComponent: bool = true,
};

mEntityID: Type = NullPlayer,
mScenemanager: *SceneManager = undefined,

pub fn AddComponent(self: Player, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mScenemanager.mECSManagerPL.AddComponent(engine_context.EngineAllocator(), self.mEntityID, new_component);
}
pub fn RemoveComponent(self: Player, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    try self.mScenemanager.mECSManagerPL.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}
pub fn GetComponent(self: Player, comptime component_type: type) ?*component_type {
    return self.mScenemanager.mECSManagerPL.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Player, comptime component_type: type) bool {
    return self.mScenemanager.mECSManagerPL.HasComponent(component_type, self.mEntityID);
}

pub fn GetName(self: Player) []const u8 {
    return self.mScenemanager.mECSManagerPL.GetComponent(PlayerNameComponent, self.mEntityID).?.*.mName.items;
}

pub fn Duplicate(self: Player) !Player {
    return try self.mScenemanager.mECSManagerPL.DuplicateEntity(self.mEntityID);
}
pub fn Delete(self: Player, engine_context: *EngineContext) !void {
    try self.mScenemanager.mECSManagerPL.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}
pub fn Possess(self: Player, entity: Entity) void {
    if (entity.GetComponent(PlayerSlotComponent)) |ps_component| {
        self.GetComponent(PossessComponent).?.mPossessedEntity = entity;
        ps_component.mPlayerEntity = self;
    } else {
        std.log.warn("Player {d} could not possess entity {d}", .{ self.mEntityID, entity.mEntityID });
    }
}

pub fn CreateChild(self: Player, engine_context: *EngineContext, child_type: ChildType, new_player_config: NewPlayerConfig) !Player {
    var child_player = Player{ .mEntityID = try self.mScenemanager.mECSManagerSC.AddChild(engine_context.EngineAllocator(), self.mEntityID, child_type), .mScenemanager = self.mScenemanager };
    try child_player.CreatePlayerConfig(engine_context, new_player_config);
    return child_player;
}

pub fn AddComponentScript(self: Player, engine_context: *EngineContext, script_asset_path: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context, script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_player = try self.CreateChild(engine_context, .Script, .{ .bAddMicComponent = false, .bAddPossessComponent = false, .bAddRenderComponent = false });

    _ = try new_script_player.AddComponent(engine_context, new_script_component);

    _ = switch (script_asset.mScriptType) {
        else => @panic("This shouldnt happen!"),
    };
}

pub fn GetIterator(self: Player, comptime iter_type: Iterator.IterType) ?Iterator {
    if (self.GetComponent(PlayerParentComponent)) |parent_component| {
        const first = switch (iter_type) {
            .Child => parent_component.mFirstEntity,
            .Script => parent_component.mFirstScript,
        };
        if (first == NullPlayer) return null;
        return Iterator{
            ._CurrentPlayer = Player{ .mEntityID = first, .mScenemanager = self.mScenemanager },
            ._FirstID = first,
        };
    } else {
        return null;
    }
}

pub fn CreatePlayerConfig(self: *Player, engine_context: *EngineContext, config: NewPlayerConfig) !void {
    if (config.bAddUUIDComponent) {
        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = GenUUID() });
        try self.mScenemanager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
    }
    if (config.bAddNameComponent) {
        var new_name_component = PlayerNameComponent{ .mAllocator = engine_context.EngineAllocator() };
        _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("New Entity");
        _ = try self.AddComponent(engine_context, new_name_component);
    }
    if (config.bAddPossessComponent) {
        _ = try self.AddComponent(engine_context, PossessComponent{});
    }
    if (config.bAddMicComponent) {
        _ = try self.AddComponent(engine_context, PlayerMic{});
    }
    if (config.bAddRenderComponent) {
        _ = try self.AddRenderTarget(engine_context);
    }
}

pub fn AddRenderTarget(self: Player, engine_context: *EngineContext) !*RenderTargetComponent {
    var new_render_comp = RenderTargetComponent{};
    const engine_allocator = engine_context.EngineAllocator();

    new_render_comp.mFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900);
    new_render_comp.mVertexArray = VertexArray.Init();
    new_render_comp.mVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
    new_render_comp.mIndexBuffer = undefined;

    const shader_asset = engine_context.mRenderer.GetSDFShader();
    try new_render_comp.mVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
    new_render_comp.mVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_render_comp.mIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_render_comp.mVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_render_comp.mVertexArray.AddVertexBuffer(engine_allocator, new_render_comp.mVertexBuffer);
    new_render_comp.mVertexArray.SetIndexBuffer(new_render_comp.mIndexBuffer);

    new_render_comp.SetViewportSize(1600, 900);
    return try self.AddComponent(engine_context, new_render_comp);
}

pub fn IsActive(self: Player) bool {
    return self.IsValidID() and self.mScenemanager.mECSManagerPL.IsActiveEntity(self.mEntityID);
}

pub fn IsValidID(self: Player) bool {
    return self.mEntityID != NullPlayer;
}
