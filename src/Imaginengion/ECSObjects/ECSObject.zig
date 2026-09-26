const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("../ECSManagers/AManager.zig");
const EManager = @import("../ECSManagers/EManager.zig");
const GCManager = @import("../ECSManagers/GCManager.zig");
const PManager = @import("../ECSManagers/PManager.zig");
const SManager = @import("../ECSManagers/SManager.zig");

const AssetHandle = @import("AssetHandle.zig");
const Entity = @import("Entity.zig");
const GameContext = @import("GameContext.zig");
const Player = @import("Player.zig");
const Scene = @import("Scene.zig");
const Voice = @import("Voice.zig");

const AComponents = @import("../ECSComponents/AComponents.zig");
const EComponents = @import("../ECSComponents/EComponents.zig");
const GCComponents = @import("../ECSComponents/GCComponents.zig");
const PComponents = @import("../ECSComponents/PComponents.zig");
const SComponents = @import("../ECSComponents/SComponents.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");

const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");
const NameComponent = @import("../ECSComponents/Shared/NameComponent.zig");
const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");
const TmplRefComponent = @import("../ECSComponents/Shared/TmplRefComponent.zig");
const EntitySceneComponent = EComponents.EntitySceneComponent;

const ScriptAsset = AComponents.ScriptAsset;

const BuiltinComponents = @import("../ECS/Components.zig");
const ParentComponent = @import("../ECS/Components.zig").ParentComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent;
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const TextSerializer = @import("../Serializer/TextSerializer.zig");

/// Template object -> its copy, built by Fill while it copies a template, so that a copied component pointing at
/// another object inside the template can be pointed at that object's copy afterwards (a component's RemapRefs).
/// Only entities for now: nothing a template is loaded with references any other kind of object yet.
pub const RefMap = struct {
    mEntities: std.AutoHashMapUnmanaged(Entity.Type, Entity) = .empty,

    /// The copy of the template entity `tmpl_entity` points at, or null if that is not part of the template.
    /// Looked up by id alone: AddComponent has already moved the reference into the copy's world by now
    pub fn Get(self: *const RefMap, tmpl_entity: Entity) ?Entity {
        if (!tmpl_entity.IsIDValid()) return null;
        return self.mEntities.get(tmpl_entity.mID);
    }
};

pub fn Core(comptime Self: type) type {
    return struct {
        comptime {
            _ValidateObject(Self);
        }

        pub const ChildType = @import("../ECS/ECSManager.zig").ChildType;
        pub const Iterator = struct {
            pub const IterType = enum {
                Child,
                Script,
            };
            _CurrentEntity: Self,
            _FirstID: Self.Type,
            _IsFirst: bool = true,

            pub fn next(self: *Iterator) ?Self {
                if (self._CurrentEntity.mID == Self.NullObject) return null;

                if (self._IsFirst) {
                    @branchHint(.cold);
                    self._IsFirst = false;
                } else {
                    if (self._CurrentEntity.mID == self._FirstID) return null;
                }

                const current = self._CurrentEntity;

                const child_component = GetComponent(current, ChildComponent(Self.Type)).?;

                self._CurrentEntity.mID = child_component.mNext;

                return current;
            }
        };
        pub const UUIDType = u64;
        pub const IDType = u32;

        pub fn AddComponent(self: Self, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
            const component_type = @TypeOf(new_component);
            const type_info = @typeInfo(component_type);
            var component = new_component;
            _ValidateComponent(Self, component_type);
            if (component_type == ScriptComponent) @compileError(std.fmt.comptimePrint("Use AddScript instead of AddComponent for {s}", .{@typeName(Self)}));

            inline for (type_info.@"struct".field_types, type_info.@"struct".field_names) |field_type, field_name| {
                if (field_type == AssetHandle) {
                    @field(component, field_name).mManager = &engine_context.mAssetManager;
                } else if (field_type == Entity or
                    field_type == GameContext or
                    field_type == Player or
                    field_type == Scene)
                {
                    @field(component, field_name).mManager = self.mManager;
                }
            }

            //the manager's AddComponent is what tags a new TransformComponent dirty, because that
            //is the one layer every route reaches (this one, and the ApplyConfig used by
            //CreateObj/CreateChild, which never comes through here)
            if (Self == Entity) {
                return try self.mManager.mEManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == GameContext) {
                return try self.mManager.mGCManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == Player) {
                return try self.mManager.mPManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == Scene) {
                return try self.mManager.mSManager.AddComponent(engine_context, self.mID, component);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }
        pub fn RemoveComponent(self: Self, engine_context: *EngineContext, comptime component_type: type) !void {
            _ValidateComponent(Self, component_type);
            if (Self == Entity) {
                try self.mManager.mEManager.RemoveComponent(engine_context, self.mID, component_type);
            } else if (Self == GameContext) {
                try self.mManager.mGCManager.RemoveComponent(engine_context, self.mID, component_type);
            } else if (Self == Player) {
                try self.mManager.mPManager.RemoveComponent(engine_context, self.mID, component_type);
            } else if (Self == Scene) {
                try self.mManager.mSManager.RemoveComponent(engine_context, self.mID, component_type);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        /// Immediate counterpart to RemoveComponent: the component is gone when this returns,
        /// instead of at end of frame. See ECSManager.RemoveComponentSync for when that is safe.
        pub fn RemoveComponentSync(self: Self, engine_context: *EngineContext, comptime component_type: type) !void {
            _ValidateComponent(Self, component_type);
            if (Self == Entity) {
                try self.mManager.mEManager.RemoveComponentSync(engine_context, self.mID, component_type);
            } else if (Self == GameContext) {
                try self.mManager.mGCManager.RemoveComponentSync(engine_context, self.mID, component_type);
            } else if (Self == Player) {
                try self.mManager.mPManager.RemoveComponentSync(engine_context, self.mID, component_type);
            } else if (Self == Scene) {
                try self.mManager.mSManager.RemoveComponentSync(engine_context, self.mID, component_type);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn GetComponent(self: Self, comptime component_type: type) ?*component_type {
            _ValidateComponent(Self, component_type);
            if (!IsActive(self)) {
                std.log.err("GetComponent called for invalid entity", .{});
                return null;
            }

            if (Self == Entity) {
                return self.mManager.mEManager.GetComponent(component_type, self.mID);
            } else if (Self == GameContext) {
                return self.mManager.mGCManager.GetComponent(component_type, self.mID);
            } else if (Self == Player) {
                return self.mManager.mPManager.GetComponent(component_type, self.mID);
            } else if (Self == Scene) {
                return self.mManager.mSManager.GetComponent(component_type, self.mID);
            } else if (Self == Voice) {
                return self.mManager.GetComponent(component_type, self.mID);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn HasComponent(self: Self, comptime component_type: type) bool {
            _ValidateComponent(Self, component_type);
            if (Self == Entity) {
                return self.mManager.mEManager.HasComponent(component_type, self.mID);
            } else if (Self == GameContext) {
                return self.mManager.mGCManager.HasComponent(component_type, self.mID);
            } else if (Self == Player) {
                return self.mManager.mPManager.HasComponent(component_type, self.mID);
            } else if (Self == Scene) {
                return self.mManager.mSManager.HasComponent(component_type, self.mID);
            } else if (Self == Voice) {
                return self.mManager.HasComponent(component_type, self.mID);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn GetUUID(self: Self) u64 {
            return GetComponent(self, UUIDComponent).?.*.ID;
        }

        pub fn GetName(self: Self) []const u8 {
            return GetComponent(self, NameComponent).?.*.mName.items;
        }
        pub fn CreateChild(self: Self, engine_context: *EngineContext, child_type: ChildType, config: Self.CreateConfig) !Self {
            if (Self == Entity) {
                return try self.mManager.mEManager.CreateChild(engine_context, self.mID, child_type, config);
            } else if (Self == GameContext) {
                return try self.mManager.mGCManager.CreateChild(engine_context, self.mID, child_type, config);
            } else if (Self == Player) {
                return try self.mManager.mPManager.CreateChild(engine_context, self.mID, child_type, config);
            } else if (Self == Scene) {
                return try self.mManager.mSManager.CreateChild(engine_context, self.mID, child_type, config);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn Duplicate(self: Self, engine_context: *EngineContext) !Self {
            if (Self == Entity) {
                return try self.mManager.mEManager.Duplicate(engine_context, self.mID);
            } else if (Self == GameContext) {
                return try self.mManager.mGCManager.Duplicate(engine_context, self.mID);
            } else if (Self == Player) {
                return try self.mManager.mPManager.Duplicate(engine_context, self.mID);
            } else if (Self == Scene) {
                return try self.mManager.mSManager.Duplicate(engine_context, self.mID);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn Delete(self: Self, engine_context: *EngineContext) !void {
            if (Self == Entity) {
                try self.mManager.mEManager.DeleteEntity(engine_context, self.mID);
            } else if (Self == GameContext) {
                try self.mManager.mGCManager.DeleteGameContext(engine_context, self.mID);
            } else if (Self == Player) {
                try self.mManager.mPManager.DeletePlayer(engine_context, self.mID);
            } else if (Self == Scene) {
                try self.mManager.mSManager.DeleteScene(engine_context, self.mID);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
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

        /// Convenience over AddScript for callers that have a path rather than a handle.
        pub fn AddComponentScript(self: Self, engine_context: *EngineContext, rel_path: []const u8, path_type: AManager.PathType) !void {
            const script_handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = path_type } });
            try self.AddScript(engine_context, script_handle);
        }

        fn _AddScriptComponent(self: Self, engine_context: *EngineContext, component: ScriptComponent) !*ScriptComponent {
            if (Self == Entity) {
                return try self.mManager.mEManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == GameContext) {
                return try self.mManager.mGCManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == Player) {
                return try self.mManager.mPManager.AddComponent(engine_context, self.mID, component);
            } else if (Self == Scene) {
                return try self.mManager.mSManager.AddComponent(engine_context, self.mID, component);
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn AddScript(self: Self, engine_context: *EngineContext, new_script_handle: AssetHandle) !Self {
            // Create the script component with the asset handle
            const new_script_component = ScriptComponent{
                .mScriptAssetHandle = new_script_handle,
            };

            //call Core's CreateChild directly: Entity's wrapper takes a config, the others don't
            const new_script_entity = try CreateChild(self, engine_context, .Script, Self.ScriptConfig);
            //AddComponent deliberately rejects ScriptComponent to push callers here, so
            //this is the one place that goes straight to the manager
            _ = try _AddScriptComponent(new_script_entity, engine_context, new_script_component);

            return new_script_entity;
        }

        /// Turns this object into a template: writes it and everything under it to the file at rel_path (see
        /// TextSerializer.SerializeTmpl), strips it down to its shell and links the shell to the new file. It is not
        /// filled back in, filled copies come from Spawn. An object that is already a copy can not be made a template.
        pub fn MakeTmpl(self: Self, engine_context: *EngineContext, rel_path: []const u8, path_type: AManager.PathType) !void {
            if (Self == AssetHandle) @compileError("an asset handle can not be made a template");
            if (HasComponent(self, TmplRefComponent)) return error.AlreadyATmplCopy;

            const abs_path = try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), rel_path, path_type);
            try TextSerializer.SerializeTmpl(engine_context, self, abs_path);

            var tmpl = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = path_type } });
            errdefer tmpl.ReleaseAsset();
            try Strip(self, engine_context);
            _ = try AddComponent(self, engine_context, TmplRefComponent{ .mTmpl = tmpl });
        }

        /// Takes this object down to its shell (its type's ShellList): removes every other saved component, its children
        /// and scripts, and a scene's entities. Deferred like any removal, so it all goes at the end of the frame.
        /// Components that are not saved (a scene's stack slot, an entity's scene, tags, ...) are left alone
        pub fn Strip(self: Self, engine_context: *EngineContext) !void {
            if (Self == AssetHandle) @compileError("an asset handle can not be stripped");

            inline for (comptime _SerializeList()) |component_type| {
                if (comptime _InShell(component_type)) continue;
                if (HasComponent(self, component_type)) try RemoveComponent(self, engine_context, component_type);
            }

            var script_iter = self.GetIterator(.Script);
            while (script_iter.next()) |script| {
                try script.Delete(engine_context);
            }

            var child_iter = self.GetIterator(.Child);
            while (child_iter.next()) |child| {
                try child.Delete(engine_context);
            }

            if (Self == Scene) {
                //each one takes the rest of its tree along
                const root_entities = try _SceneRootEntities(self, engine_context);
                for (root_entities.items) |entity_id| {
                    try self.GetEntity(entity_id).Delete(engine_context);
                }
            }
        }

        /// Links this object to the template `tmpl` and fills it from it (see Fill), taking its own reference on the handle
        pub fn SetTmpl(self: Self, engine_context: *EngineContext, tmpl: AssetHandle) !void {
            tmpl.RetainAsset();
            _ = AddComponent(self, engine_context, TmplRefComponent{ .mTmpl = tmpl }) catch |err| {
                var unused_handle = tmpl;
                unused_handle.ReleaseAsset();
                return err;
            };
            try Fill(self, engine_context);
        }

        /// Makes this object a copy of the template its TmplRefComponent points at. The loaded template's components
        /// are copied onto it, except the ones it already has (a shell keeps its own UUID, Name, Transform, ...), and
        /// so are the template's scripts, children and, for a scene, its entities. Nothing copied gets a UUID. A copied
        /// component that points at another object inside the template is pointed at that object's copy (RemapRefs).
        pub fn Fill(self: Self, engine_context: *EngineContext) !void {
            if (Self == AssetHandle) @compileError("an asset handle can not be filled from a template");

            const tmpl_ref = GetComponent(self, TmplRefComponent) orelse return error.NoTmplRef;
            //by value: loading more assets while copying (textures, scripts, ...) can move the storage this points into
            const tmpl = (try tmpl_ref.mTmpl.GetAsset(engine_context, AComponents.ObjectAssetFor(Self))).mObject;

            var ref_map: RefMap = .{};
            try _CopyObject(tmpl, self, engine_context, &ref_map);
            //after everything is copied, so every copy a reference could point at exists.
            //the shell's own components hold no references, so it is fine that they go through this too
            try _RemapRefs(self, engine_context, &ref_map);
        }

        /// Copies the template object `tmpl` onto `target`: its components, then its scripts, children and a scene's entities
        fn _CopyObject(tmpl: Self, target: Self, engine_context: *EngineContext, ref_map: *RefMap) anyerror!void {
            if (Self == Entity) try ref_map.mEntities.put(engine_context.FrameAllocator(), tmpl.mID, target);

            inline for (comptime _SerializeList()) |component_type| {
                //a copy gets no UUID, and whatever the target already has stays as it is
                if (component_type != UUIDComponent and !HasComponent(target, component_type)) {
                    if (GetComponent(tmpl, component_type)) |tmpl_component| {
                        //a component that owns memory copies itself, anything else is a plain value copy (as DuplicateEntity does)
                        const component = if (@hasDecl(component_type, "Clone")) try tmpl_component.Clone(engine_context) else tmpl_component.*;
                        const new_component = try AddComponent(target, engine_context, component);
                        //whatever a component hooks up when it is loaded from a file it hooks up here too, e.g. a scene's stack slot
                        if (@hasDecl(component_type, "PostParse")) try new_component.PostParse(engine_context, target);
                    }
                }
            }

            if (@hasDecl(Self, "AddScript")) {
                var script_iter = tmpl.GetIterator(.Script);
                while (script_iter.next()) |tmpl_script| {
                    //AddScript keeps the handle it is given, and the template keeps its own
                    var script_handle = GetComponent(tmpl_script, ScriptComponent).?.mScriptAssetHandle;
                    script_handle.RetainAsset();
                    errdefer script_handle.ReleaseAsset();
                    try target.AddScript(engine_context, script_handle);
                }
            }

            var child_iter = tmpl.GetIterator(.Child);
            while (child_iter.next()) |tmpl_child| {
                const child = try target.CreateChild(engine_context, .Entity, Self.BlankConfig);
                try _CopyObject(tmpl_child, child, engine_context, ref_map);
            }

            if (Self == Scene) {
                //only the top level entities, each one brings the rest of its tree along
                const tmpl_roots = try _SceneRootEntities(tmpl, engine_context);
                for (tmpl_roots.items) |tmpl_entity_id| {
                    const entity = try target.CreateEntity(engine_context, Entity.BlankConfig);
                    try Core(Entity)._CopyObject(tmpl.GetEntity(tmpl_entity_id), entity, engine_context, ref_map);
                }
            }
        }

        /// Lets each component of `target` and everything under it that references other objects point them at their copies
        fn _RemapRefs(target: Self, engine_context: *EngineContext, ref_map: *const RefMap) anyerror!void {
            inline for (comptime _SerializeList()) |component_type| {
                if (@hasDecl(component_type, "RemapRefs")) {
                    if (GetComponent(target, component_type)) |component| component.RemapRefs(ref_map);
                }
            }

            var child_iter = target.GetIterator(.Child);
            while (child_iter.next()) |child| {
                try _RemapRefs(child, engine_context, ref_map);
            }

            if (Self == Scene) {
                const root_entities = try _SceneRootEntities(target, engine_context);
                for (root_entities.items) |entity_id| {
                    try Core(Entity)._RemapRefs(target.GetEntity(entity_id), engine_context, ref_map);
                }
            }
        }

        /// The scene's entities that are not children of another entity
        fn _SceneRootEntities(scene: Scene, engine_context: *EngineContext) !std.ArrayList(Entity.Type) {
            const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
            const EntityChildQuery = GroupQuery{ .Component = ChildComponent(Entity.Type) };
            return try scene.GetEntityGroup(engine_context.FrameAllocator(), .{
                .Not = .{
                    .mFirst = &EntitySceneQuery,
                    .mSecond = &EntityChildQuery,
                },
            });
        }

        /// Whether component_type is part of this type's shell (see Strip)
        fn _InShell(comptime component_type: type) bool {
            const shell_list = if (Self == Entity)
                EComponents.ShellList
            else if (Self == GameContext)
                GCComponents.ShellList
            else if (Self == Player)
                PComponents.ShellList
            else if (Self == Scene)
                SComponents.ShellList
            else
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));

            for (shell_list) |shell_type| {
                if (shell_type == component_type) return true;
            }
            return false;
        }

        /// The components an object of this type is saved with, which are also what a copy is made of
        fn _SerializeList() []const type {
            if (Self == Entity) {
                return &EComponents.SerializeList;
            } else if (Self == GameContext) {
                return &GCComponents.SerializeList;
            } else if (Self == Player) {
                return &PComponents.SerializeList;
            } else if (Self == Scene) {
                return &SComponents.SerializeList;
            } else {
                @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
            }
        }

        pub fn IsActive(self: Self) bool {
            if (!self.IsIDValid()) return false;
            return blk: {
                if (Self == AssetHandle or Self == Voice) {
                    break :blk self.mManager.IsActiveObj(self.mID);
                } else if (Self == Entity) {
                    break :blk self.mManager.mEManager.IsActiveObj(self.mID);
                } else if (Self == GameContext) {
                    break :blk self.mManager.mGCManager.IsActiveObj(self.mID);
                } else if (Self == Player) {
                    break :blk self.mManager.mPManager.IsActiveObj(self.mID);
                } else if (Self == Scene) {
                    break :blk self.mManager.mSManager.IsActiveObj(self.mID);
                } else {
                    @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
                }
            };
        }

        pub fn IsIDValid(self: Self) bool {
            return if (self.mID != Self.NullObject) true else false;
        }

        pub fn Invalidate(self: *Self) void {
            self.mID = Self.NullObject;
        }

        pub fn _ValidateEntity(self: Self, label: []const u8) !void {
            if (!IsActive(self)) {
                std.log.err("Made call on invalid Entity. Call: {s}", .{label});
                return error.InvalidEntity;
            }
            return;
        }

        fn _ValidateComponent(obj_t: type, comptime component_type: type) void {
            //the ECS supplies these itself, so they are in no object's component list
            if (component_type == ParentComponent(obj_t.Type) or
                component_type == ChildComponent(obj_t.Type) or
                component_type == BuiltinComponents.MainObjectComponent or
                component_type == BuiltinComponents.EntityTagComponent or
                component_type == BuiltinComponents.ScriptTagComponent) return;

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
                } else if (obj_t == Voice) {
                    break :blk VComponents.ComponentsList;
                } else {
                    @compileError(std.fmt.comptimePrint("This isnt implemented yet for object type: {s}", .{@typeName(Self)}));
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
            } else if (obj_t == Voice) {
                is_valid = true;
            }

            if (!is_valid) {
                @compileError(std.fmt.comptimePrint("Type is not yet a valid ECS Object {s}", .{@typeName(obj_t)}));
            }
        }
    };
}
