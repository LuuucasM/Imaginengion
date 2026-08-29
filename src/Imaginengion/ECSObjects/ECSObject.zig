const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("../ECSManagers.zig/AManager.zig");
const EManager = @import("../ECSManagers.zig/EManager.zig");
const GCManager = @import("../ECSManagers.zig/GCManager.zig");
const PManager = @import("../ECSManagers.zig/PManager.zig");
const SManager = @import("../ECSManagers.zig/SManager.zig");

const AssetHandle = @import("AssetHandle.zig");
const Entity = @import("Entity.zig");
const GameContext = @import("GameContext.zig");
const Player = @import("Player.zig");
const Scene = @import("Scene.zig");

const AComponents = @import("../ECSComponents/AComponents.zig");
const EComponents = @import("../ECSComponents/EComponents.zig");
const GCComponents = @import("../ECSComponents/GCComponents.zig");
const PComponents = @import("../ECSComponents/PComponents.zig");
const SComponents = @import("../ECSComponents/SComponents.zig");

const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");
const NameComponent = @import("../ECSComponents/Shared/NameComponent.zig");
const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");

const ScriptAsset = AComponents.ScriptAsset;

const ParentComponent = @import("../ECS/Components.zig").ParentComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent;

pub fn Core(comptime Self: type) type {
    return struct {
        comptime {
            _ValidateObject(Self);
        }

        pub const ChildType = enum {
            Entity,
            Script,
        };
        pub const Iterator = struct {
            pub const IterType = enum {
                Child,
                Script,
            };
            _CurrentEntity: Self,
            _FirstID: Self.Type,
            _IsFirst: bool = true,

            pub fn next(self: *Iterator) ?Entity {
                if (self._IsFirst) {
                    @branchHint(.cold);
                    self._IsFirst = false;
                } else {
                    if (self._CurrentEntity.mID == self._FirstID) return null;
                }

                const entity = self._CurrentEntity;

                const entity_child_component = entity.GetComponent(ChildComponent(Self.Type)).?;

                self._CurrentEntity = Entity{ .mEntityID = entity_child_component.mNext, .mSceneManager = entity.mSceneManager };

                return entity;
            }
        };
        pub const UUIDType = u64;
        pub const IDType = u32;

        pub const empty: Self = .{
            .mID = Self.NullObject,
            .mManager = undefined,
        };

        pub fn AddComponent(self: Self, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
            const component_type = @TypeOf(new_component);
            const type_info = @typeInfo(component_type);
            var component = new_component;
            _ValidateComponent(Self, component_type);

            if (component_type == ScriptComponent) @compileError(std.fmt.comptimePrint("Use AddScript instead of AddComponent for {s}", .{@typeName(Self)}));

            inline for (type_info.@"struct".field_types, type_info.@"struct".field_names) |field_type, field_name| {
                if (field_type == AssetHandle) {
                    @field(component, field_name).mManager = &engine_context.mAManager;
                } else if (field_type == Entity) {
                    @field(component, field_name).mManager = self.mManager;
                } else if (field_type == GameContext) {
                    @field(component, field_name).mManager = self.mManager;
                } else if (field_type == Player) {
                    @field(component, field_name).mManager = self.mManager;
                } else if (field_type == Scene) {
                    @field(component, field_name).mManager = self.mManager;
                }
            }

            if (Self == AssetHandle) {
                return self.mManager.AddComponent(engine_context.EngineAllocator(), self.mID, component);
            } else if (Self == Entity) {
                return self.mManager.mEManager.AddComponent(engine_context.EngineAllocator(), self.mID, component);
            } else if (Self == GameContext) {
                return self.mManager.mGCManager.AddComponent(engine_context.EngineAllocator(), self.mID, component);
            } else if (Self == Player) {
                return self.mManager.mPManager.AddComponent(engine_context.EngineAllocator(), self.mID, component);
            } else if (Self == Scene) {
                return self.mManager.mSManager.AddComponent(engine_context.EngineAllocator(), self.mID, component);
            }
        }
        pub fn RemoveComponent(self: Self, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
            _ValidateComponent(Self, component_type);
            if (Self == AssetHandle) {
                self.mManager.RemoveComponent(engine_allocator, component_type, self.mID);
            } else if (Self == Entity) {
                self.mManager.mEManager.RemoveComponent(engine_allocator, component_type, self.mID);
            } else if (Self == GameContext) {
                self.mManager.mGCManager.RemoveComponent(engine_allocator, component_type, self.mID);
            } else if (Self == Player) {
                self.mManager.mPManager.RemoveComponent(engine_allocator, component_type, self.mID);
            } else if (Self == Scene) {
                self.mManager.mSManager.RemoveComponent(engine_allocator, component_type, self.mID);
            }
        }

        pub fn GetComponent(self: Self, comptime component_type: type) ?*component_type {
            _ValidateComponent(Self, component_type);
            if (Self == AssetHandle) {
                self.mManager.GetComponent(component_type, self.mID);
            } else if (Self == Entity) {
                self.mManager.mEManager.GetComponent(component_type, self.mID);
            } else if (Self == GameContext) {
                self.mManager.mGCManager.GetComponent(component_type, self.mID);
            } else if (Self == Player) {
                self.mManager.mPManager.GetComponent(component_type, self.mID);
            } else if (Self == Scene) {
                self.mManager.mSManager.GetComponent(component_type, self.mID);
            }
        }

        pub fn HasComponent(self: Self, comptime component_type: type) bool {
            _ValidateComponent(Self, component_type);
            if (Self == AssetHandle) {
                self.mManager.HasComponent(component_type, self.mID);
            } else if (Self == Entity) {
                self.mManager.mEManager.HasComponent(component_type, self.mID);
            } else if (Self == GameContext) {
                self.mManager.mGCManager.HasComponent(component_type, self.mID);
            } else if (Self == Player) {
                self.mManager.mPManager.HasComponent(component_type, self.mID);
            } else if (Self == Scene) {
                self.mManager.mSManager.HasComponent(component_type, self.mID);
            }
        }

        pub fn GetUUID(self: Self) u64 {
            return GetComponent(self, UUIDComponent).?.*.ID;
        }

        pub fn GetName(self: Self) []const u8 {
            return GetComponent(self, NameComponent).?.*.mName.items;
        }
        pub fn CreateChild(self: Self, engine_context: *EngineContext, child_type: ChildType) !Self {
            if (Self == AssetHandle) {
                return .{ .mID = try self.mManager.AddChild(engine_context.EngineAllocator(), self.mID, child_type), .mManager = self.mManager };
            } else if (Self == Entity) {
                return .{ .mID = try self.mManager.mEManager.AddChild(engine_context.EngineAllocator(), self.mID, child_type), .mManager = self.mManager };
            } else if (Self == GameContext) {
                return .{ .mID = try self.mManager.mGCManager.AddChild(engine_context.EngineAllocator(), self.mID, child_type), .mManager = self.mManager };
            } else if (Self == Player) {
                return .{ .mID = try self.mManager.mPManager.AddChild(engine_context.EngineAllocator(), self.mID, child_type), .mManager = self.mManager };
            } else if (Self == Scene) {
                return .{ .mID = try self.mManager.mSManager.AddChild(engine_context.EngineAllocator(), self.mID, child_type), .mManager = self.mManager };
            }
        }

        pub fn Duplicate(self: Self) !Self {
            if (Self == AssetHandle) {
                return .{ .mID = try self.mManager.Duplicate(self.mID), .mManager = self.mManager };
            } else if (Self == Entity) {
                return .{ .mID = try self.mManager.mAManager.Duplicate(self.mID), .mManager = self.mManager };
            } else if (Self == GameContext) {
                return .{ .mID = try self.mManager.mEManager.Duplicate(self.mID), .mManager = self.mManager };
            } else if (Self == Player) {
                return .{ .mID = try self.mManager.mPManager.Duplicate(self.mID), .mManager = self.mManager };
            } else if (Self == Scene) {
                return .{ .mID = try self.mManager.mSManager.Duplicate(self.mID), .mManager = self.mManager };
            }
        }

        pub fn Delete(self: Self, engine_context: *EngineContext) !void {
            if (Self == AssetHandle) {
                try self.mManager.Delete(engine_context.EngineAllocator(), self.mID);
            } else if (Self == Entity) {
                try self.mManager.mAManager.Delete(engine_context.EngineAllocator(), self.mID);
            } else if (Self == GameContext) {
                try self.mManager.mEManager.Delete(engine_context.EngineAllocator(), self.mID);
            } else if (Self == Player) {
                try self.mManager.mPManager.Delete(engine_context.EngineAllocator(), self.mID);
            } else if (Self == Scene) {
                try self.mManager.mSManager.Delete(engine_context.EngineAllocator(), self.mID);
            }
        }

        pub fn GetIterator(self: Self, comptime iter_type: Iterator.IterType) Iterator {
            const INVALID_ITER: Iterator = .{ ._CurrentEntity = .{ .mID = Self.NullObject, .mManager = self.mManager }, ._FirstID = Self.NullObject };
            if (GetComponent(self, ParentComponent(Self.Type))) |parent_component| {
                const first = switch (iter_type) {
                    .Child => parent_component.mFirstEntity,
                    .Script => parent_component.mFirstScript,
                };
                if (first == Self.NullObject) return INVALID_ITER;
                return Iterator{
                    ._CurrentEntity = .{ .mID = first, .mManager = self.mManager },
                    ._FirstID = first,
                };
            } else {
                return INVALID_ITER;
            }
        }

        pub fn AddScript(self: Self, engine_context: *EngineContext, new_script_handle: AssetHandle) !Self {
            // Create the script component with the asset handle
            const new_script_component = ScriptComponent{
                .mScriptAssetHandle = new_script_handle,
            };

            const new_script_entity = try self.CreateChild(engine_context, .Script, .{ .bAddName = false, .bAddTransform = false, .bAddUUID = false });
            _ = try AddComponent(new_script_entity, engine_context, new_script_component);

            return new_script_entity;
        }

        pub fn IsActive(self: Self) bool {
            const is_id_valid = self.IsIDValid();
            const is_active_obj = blk: {
                if (Self == AssetHandle) {
                    break :blk try self.mManager.IsActiveEntity(self.mID);
                } else if (Self == Entity) {
                    break :blk try self.mManager.mEManager.IsActiveEntity(self.mID);
                } else if (Self == GameContext) {
                    break :blk try self.mManager.mGCManager.IsActiveEntity(self.mID);
                } else if (Self == Player) {
                    break :blk try self.mManager.mPManager.IsActiveEntity(self.mID);
                } else if (Self == Scene) {
                    break :blk try self.mManager.mSManager.IsActiveEntity(self.mID);
                }
            };
            return is_id_valid and is_active_obj;
        }

        pub fn IsIDValid(self: Self) bool {
            return if (self.mID != Self.NullObject) true else false;
        }

        pub fn Invalidate(self: *Self) void {
            self.mID = Self.NullObject;
        }

        fn _ValidateComponent(obj_t: type, comptime component_type: type) void {
            comptime var is_valid = false;

            const components_list = blk: {
                if (obj_t == AssetHandle) {
                    break :blk AComponents.ComponentsList;
                } else if (obj_t == Entity) {
                    break :blk EComponents.ComponentsList;
                } else if (obj_t == GameContext) {
                    break :blk GCComponents.ComponentsList;
                } else if (obj_t == Player) {
                    break :blk PComponents.ComponentsList;
                } else if (obj_t == Scene) {
                    break :blk SComponents.ComponentsList;
                } else {
                    @compileError(std.fmt.comptimePrint("ECSObject currently does not support: {s}", .{@typeName(Self)}));
                }
            };

            inline for (components_list) |list_type| {
                if (component_type == list_type) {
                    is_valid = true;
                }
            }
            if (!is_valid) {
                @compileError(std.fmt.comptimePrint("Component Type {s} is not a valid component for ECS Object type {s}", .{ @typeName(component_type), @typeName(obj_t) }));
            }
        }

        fn _ValidateObject(obj_t: type) void {
            comptime var is_valid = false;
            if (obj_t == AssetHandle) {
                is_valid = true;
            } else if (obj_t == Entity) {
                is_valid = true;
            } else if (obj_t == GameContext) {
                is_valid = true;
            } else if (obj_t == Player) {
                is_valid = true;
            } else if (obj_t == Scene) {
                is_valid = true;
            }

            if (!is_valid) {
                @compileError(std.fmt.comptimePrint("Type is not a valid ECS Object {s}", .{@typeName(obj_t)}));
            }
        }
    };
}
