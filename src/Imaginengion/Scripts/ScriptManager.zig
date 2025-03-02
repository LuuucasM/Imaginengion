const std = @import("std");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const Script = @import("../Assets/Assets/Script.zig");
const Entity = @import("../GameObjects/Entity.zig");
const ScriptManager = @This();

const ScriptPos = enum {
    PreInputScripts,
    PostInputScripts,
    PrePhysicsScripts,
    PostPhysicsScripts,
    PreGameLogicScripts,
    PostGameLogicScripts,
    PreRenderScripts,
    PostRenderScripts,
    PreAudioScripts,
    PostAudioScripts,
    PreNetworkingScripts,
    PostNetworkingScripts,
};

const ObjectScript = struct {
    mEntity: Entity,
    mAssetHandle: AssetHandle,
};

mPreInputScripts: ArraySet(u32),
mPostInputScripts: ArraySet(u32),
mPrePhysicsScripts: ArraySet(u32),
mPostPhysicsScripts: ArraySet(u32),
mPreGameLogicScripts: ArraySet(u32),
mPostGameLogicScripts: ArraySet(u32),
mPreRenderScripts: ArraySet(u32),
mPostRenderScripts: ArraySet(u32),
mPreAudioScripts: ArraySet(u32),
mPostAudioScripts: ArraySet(u32),
mPreNetworkingScripts: ArraySet(u32),
mPostNetworkingScripts: ArraySet(u32),

pub fn Init(engine_allocator: std.mem.Allocator) !ScriptManager {
    return ScriptManager{
        .mPreInputScripts = ArraySet(u32).init(engine_allocator),
        .mPostInputScripts = ArraySet(u32).init(engine_allocator),
        .mPrePhysicsScripts = ArraySet(u32).init(engine_allocator),
        .mPostPhysicsScripts = ArraySet(u32).init(engine_allocator),
        .mPreGameLogicScripts = ArraySet(u32).init(engine_allocator),
        .mPostGameLogicScripts = ArraySet(u32).init(engine_allocator),
        .mPreRenderScripts = ArraySet(u32).init(engine_allocator),
        .mPostRenderScripts = ArraySet(u32).init(engine_allocator),
        .mPreAudioScripts = ArraySet(u32).init(engine_allocator),
        .mPostAudioScripts = ArraySet(u32).init(engine_allocator),
        .mPreNetworkingScripts = ArraySet(u32).init(engine_allocator),
        .mPostNetworkingScripts = ArraySet(u32).init(engine_allocator),
    };
}

pub fn Deinit(self: *ScriptManager) void {
    self.mPreInputScripts.deinit();
    self.mPostInputScripts.deinit();
    self.mPrePhysicsScripts.deinit();
    self.mPostPhysicsScripts.deinit();
    self.mPreGameLogicScripts.deinit();
    self.mPostGameLogicScripts.deinit();
    self.mPreRenderScripts.deinit();
    self.mPostRenderScripts.deinit();
    self.mPreAudioScripts.deinit();
    self.mPostAudioScripts.deinit();
    self.mPreNetworkingScripts.deinit();
    self.mPostNetworkingScripts.deinit();
}

pub fn RegisterScript(self: *ScriptManager, comptime script_type: type, entity: Entity, asset_handle: AssetHandle) void {
    if (@hasDecl(script_type, "PreInputUpdate")) {
        self.mPreInputScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostInputUpdate")) {
        self.mPostInputScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PrePhysicsUpdate")) {
        self.mPrePhysicsScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostPhysicsUpdate")) {
        self.mPostPhysicsScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PreGameLogicUpdate")) {
        self.mPreGameLogicScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostGameLogicUpdate")) {
        self.mPostGameLogicScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PreRenderUpdate")) {
        self.mPreRenderScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostRenderUpdate")) {
        self.mPostRenderScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PreAudioUpdate")) {
        self.mPreAudioScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostAudioUpdate")) {
        self.mPostAudioScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PreNetworkingUpdate")) {
        self.mPreNetworkingScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
    if (@hasDecl(script_type, "PostNetworkingUpdate")) {
        self.mPostNetworkingScripts.add(.{ .mEntity = entity, .mAssetHandle = asset_handle });
    }
}

pub fn UnregisterScript(self: *ScriptManager, comptime script_type: type, asset_handle: AssetHandle) void {
    if (@hasDecl(script_type, "PreInputUpdate")) {
        self.mPreInputScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostInputUpdate")) {
        self.mPostInputScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PrePhysicsUpdate")) {
        self.mPrePhysicsScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostPhysicsUpdate")) {
        self.mPostPhysicsScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PreGameLogicUpdate")) {
        self.mPreGameLogicScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostGameLogicUpdate")) {
        self.mPostGameLogicScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PreRenderUpdate")) {
        self.mPreRenderScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostRenderUpdate")) {
        self.mPostRenderScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PreAudioUpdate")) {
        self.mPreAudioScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostAudioUpdate")) {
        self.mPostAudioScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PreNetworkingUpdate")) {
        self.mPreNetworkingScripts.remove(asset_handle);
    }
    if (@hasDecl(script_type, "PostNetworkingUpdate")) {
        self.mPostNetworkingScripts.remove(asset_handle);
    }
}

pub fn RunScript(self: ScriptManager, script_pos: ScriptPos) void {
    const arr = switch (script_pos) {
        .PreInputScripts => self.mPreInputScripts,
        .PostInputScripts => self.mPostInputScripts,
        .PrePhysicsScripts => self.mPrePhysicsScripts,
        .PostPhysicsScripts => self.mPostPhysicsScripts,
        .PreGameLogicScripts => self.mPreGameLogicScripts,
        .PostGameLogicScripts => self.mPostGameLogicScripts,
        .PreRenderScripts => self.mPreRenderScripts,
        .PostRenderScripts => self.mPostRenderScripts,
        .PreAudioScripts => self.mPreAudioScripts,
        .PostAudioScripts => self.mPostAudioScripts,
        .PreNetworkingScripts => self.mPreNetworkingScripts,
        .PostNetworkingScripts => self.mPostNetworkingScripts,
    };
    const iter = arr.iterator();
    while (iter.next()) |entry| {
        const asset_handle = entry.key_ptr.*;
        const script_asset = asset_handle.GetAsset(Script);
        switch (script_pos) {
            .PreInputScripts => script_asset.PreInputScripts(), //need to feed the arguments here somehow
            .PostInputScripts => self.mPostInputScripts,
            .PrePhysicsScripts => self.mPrePhysicsScripts,
            .PostPhysicsScripts => self.mPostPhysicsScripts,
            .PreGameLogicScripts => self.mPreGameLogicScripts,
            .PostGameLogicScripts => self.mPostGameLogicScripts,
            .PreRenderScripts => self.mPreRenderScripts,
            .PostRenderScripts => self.mPostRenderScripts,
            .PreAudioScripts => self.mPreAudioScripts,
            .PostAudioScripts => self.mPostAudioScripts,
            .PreNetworkingScripts => self.mPreNetworkingScripts,
            .PostNetworkingScripts => self.mPostNetworkingScripts,
        }
    }
}
