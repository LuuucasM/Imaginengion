const std = @import("std");
const SystemsList = @import("../Systems.zig").SystemsList;
const ComponentManager = @import("../../ECS/ComponentManager.zig");
const RenderManager = @import("../../Renderer/Renderer.zig");
const ArraySet = @import("../../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const StaticSkipField = @import("../../Core/SkipField.zig").StaticSkipField;
const RenderSystem = @This();

const Components = @import("../Components.zig");
const EComponents = Components.EComponents;
const TransformComponent = Components.TransformComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const CircleRenderComponent = Components.CircleRenderComponent;

mSkipFieldSig: StaticSkipField(32 + 1),
mEntitySet: ArraySet(u32),

pub fn Init(allocator: std.mem.Allocator) RenderSystem {
    return RenderSystem{
        .mEntitySet = ArraySet(u32).init(allocator),
        .mSkipFieldSig = StaticSkipField(32 + 1).Init(.AllSkip),
    };
}

pub fn Deinit(self: *RenderSystem) void {
    self.mEntitySet.deinit();
}

pub fn OnUpdate(self: RenderSystem, component_manager: ComponentManager) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //make lists of different renderables
    var sprite_entities = std.ArrayList(u32).init(allocator);
    var circle_entities = std.ArrayList(u32).init(allocator);

    var iter = self.mEntitySet.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        if (component_manager.HasComponent(SpriteRenderComponent, entity_id) == true) {
            try sprite_entities.append(entity_id);
        } else if (component_manager.HasComponent(CircleRenderComponent, entity_id) == true) {
            try circle_entities.append(entity_id);
        }
    }

    //culling
    const end_index_sprites = Culling(component_manager, sprite_entities, SpriteRenderComponent);
    const end_index_circles = Culling(component_manager, circle_entities, CircleRenderComponent);

    //other optimization passes

    for (0..end_index_sprites) |i| {
        const entity_id = sprite_entities.items[i];
        const transform_component = component_manager.GetComponent(TransformComponent, entity_id);
        const sprite_render_component = component_manager.GetComponent(SpriteRenderComponent, entity_id);
        RenderManager.DrawSprite(transform_component.GetTransformMatrix(), sprite_render_component.mColor, 0, sprite_render_component.mTilingFactor);
        //TODO: ^^^ up here on this line, change texture index to actual texture index
        //TODO: just keeping texture index 0 for now because I havnt added the texture list or anything yet to this render sytstem
    }

    //circles
    for (0..end_index_circles) |i| {
        const entity_id = circle_entities.items[i];
        const transform_component = component_manager.GetComponent(TransformComponent, entity_id);
        const circle_render_component = component_manager.GetComponent(CircleRenderComponent, entity_id);
        RenderManager.DrawCircle(transform_component.GetTransformMatrix(), circle_render_component.mColor, circle_render_component.mThickness, circle_render_component.mFade);
    }
}

pub fn AddEntity(self: *RenderSystem, entity_id: u32) !void {
    _ = try self.mEntitySet.add(entity_id);
}

pub fn RemoveEntity(self: *RenderSystem, entity_id: u32) void {
    _ = self.mEntitySet.remove(entity_id);
}

pub fn GetComponentField(self: RenderSystem) StaticSkipField(32 + 1) {
    return self.mSkipFieldSig;
}

pub const Ind: usize = blk: {
    for (SystemsList, 0..) |system_type, i| {
        if (system_type == RenderSystem) {
            break :blk i;
        }
    }
};

fn Culling(component_manager: ComponentManager, entity_list: std.ArrayList(u32), component_type: type) usize {
    var write_index: usize = 0;
    var read_index: usize = 0;

    while (read_index < entity_list.items.len) : (read_index += 1) {
        const entity_id = entity_list.items[read_index];
        const component = component_manager.GetComponent(component_type, entity_id);
        std.debug.assert(@hasField(component_type, "mShouldRender"));

        if (component.mShouldRender == true) {
            const temp = entity_list.items[write_index];
            entity_list.items[write_index] = entity_list.items[read_index];
            entity_list.items[read_index] = temp;
            write_index += 1;
        }
    }
    return write_index;
}
