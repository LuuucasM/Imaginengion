const std = @import("std");
const Scripts = @import("ScriptTypes.zig");
const ScriptsList = Scripts.ComponentsList;
const EntityScript = Scripts.EntityScript;
const AnimationScript = Scripts.AnimationScript;
const CollisionScript = Scripts.CollisionScript;
const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("../GameObjects/Entity.zig");
const ScriptManager = @This();

mECSManager: ECSManager,

pub fn Init(engine_allocator: std.mem.Allocator) !ScriptManager {
    return ScriptManager{ .mECSManager = ECSManager.Init(engine_allocator, ScriptsList) };
}

pub fn Deinit(self: *ScriptManager) void {
    self.mECSManager.Deinit();
}

pub fn StartEntityScript(self: *ScriptManager, entity: Entity, script_mask: u16, script: std.DynLib) !u32 {
    const new_entity = try self.mECSManager.CreateEntity();
    const new_script = EntityScript{ entity, script };
    _ = try self.mECSManager.AddComponent(EntityScript, new_entity, new_script);

    //go through all the tag types and see if we need to add it
    inline for (0..ScriptsList.len) |i| {
        const mask: u16 = @intCast(1 << i);
        if (script_mask & mask > 0) {
            try self.mECSManager.AddComponent(ScriptsList[i], new_entity, null);
        }
    }
}

pub fn StopScript(self: *ScriptManager, script_entity_id: u32) !void {
    try self.mECSManager.DestroyEntity(script_entity_id);
}

pub fn RunScript(self: ScriptManager, script_tag: type) !void {
    const group = try self.mECSManager.GetGroup(.{ .Component = script_tag });
    for (group.items) |entity_id| {
        if (self.mECSManager.HasComponent(EntityScript, entity_id)) {
            const entity_script = self.mECSManager.GetComponent(EntityScript, entity_id);
            std.debug.print("type name in run script: {s}\n", .{@typeName(script_tag)});
            if (entity_script.mScript.lookup(fn (Entity) void, @typeName(script_tag))) |func| {
                @call(.auto, func, .{entity_script.mEntity});
            }
        }
        if (self.mECSManager.HasComponent(CollisionScript, entity_id)) {
            const entity_script = self.mECSManager.GetComponent(CollisionScript, entity_id);
            std.debug.print("type name in run script: {s}\n", .{@typeName(script_tag)});
            if (entity_script.mScript.lookup(fn (Entity, Entity) void, @typeName(script_tag))) |func| {
                @call(.auto, func, .{ entity_script.mEntity1, entity_script.mEntity2 });
            }
        }
        if (self.mECSManager.HasComponent(AnimationScript, entity_id)) {
            const entity_script = self.mECSManager.GetComponent(AnimationScript, entity_id);
            std.debug.print("type name in run script: {s}\n", .{@typeName(script_tag)});
            if (entity_script.mScript.lookup(fn (Entity) void, @typeName(script_tag))) |func| {
                @call(.auto, func, .{entity_script.mEntity});
            }
        }
    }
}
