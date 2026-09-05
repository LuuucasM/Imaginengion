const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("AManager.zig");
const EManager = @import("EManager.zig");
const GCManager = @import("GCManager.zig");
const PManager = @import("PManager.zig");
const SManager = @import("SManager.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

pub fn Core(comptime Self: type) type {
    return struct {
        comptime {
            _ValidateObject(Self);
        }

        pub fn Init(self: Self, engine_allocator: std.mem.Allocator) !void {
            try self.mECSManager.Init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            try self.mECSManager.Deinit(engine_context.EngineAllocator());
            self.mUUIDToWorldID.deinit(engine_context.EngineAllocator());
            self.mResolveUUIDList.deinit(engine_context.EngineAllocator());
            self.mEventManager.Deinit(engine_context.EngineAllocator());
        }

        pub fn CreateObject(self: *Self, engine_allocator: std.mem.Allocator) ObjectReturnType(Self) {
            return .{ .mID = self.mECSManager.CreateEntity(engine_allocator), .mManager = self };
        }

        //pub fn SaveObject()

        //pub fn SaveObjectAs()

        //pub fn GetGroup(self: *AManager, engine_context: *EngineContext) std.ArrayList(AssetHandle.Type) {}

        //pub fn clearAndFree(self: *AManager, engine_context: *EngineContext) !void {}

        //pub fn Copy(self: *AManager, engine_context: *EngineContext, other_scene: *AManager) !void {}

        pub fn AddUUID(self: *Self, engine_allocator: std.mem.Allocator, uuid: u64, world_id: Self.WorldIDT) !void {
            try self.mUUIDToWlrdID.put(engine_allocator, uuid, world_id);
        }

        //pub fn RemoveUUID(self: *AManager, uuid: u64) void {}

        //pub fn GetWorldID(self: *AManager, uuid: u64) ?usize {}

        //pub fn AddResolveUUID(self: *AManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {}

        fn _ValidateObject(manager_t: type) void {
            comptime var is_valid = false;
            if (manager_t == AManager) {
                is_valid = true;
            } else if (manager_t == EManager) {
                is_valid = true;
            } else if (manager_t == GCManager) {
                is_valid = true;
            } else if (manager_t == PManager) {
                is_valid = true;
            } else if (manager_t == SManager) {
                is_valid = true;
            }

            if (!is_valid) {
                @compileError(std.fmt.comptimePrint("Type is not yet a valid ECS Object {s}", .{@typeName(manager_t)}));
            }
        }

        fn ObjectReturnType(manager_t: type) type {
            if (manager_t == AManager) {
                return AssetHandle;
            } else if (manager_t == EManager) {
                return Entity;
            } else if (manager_t == GCManager) {
                return GameContext;
            } else if (manager_t == PManager) {
                return Player;
            } else if (manager_t == SManager) {
                return Scene;
            }
        }
    };
}
