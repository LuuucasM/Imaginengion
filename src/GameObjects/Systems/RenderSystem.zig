const std = @import("std");
const SystemsList = @import("../Systems.zig").SystemsList;
const ComponentManager = @import("../../ECS/ComponentManager.zig");
const RenderManager = @import("../../Renderer/Renderer.zig");
const RenderSystem = @This();

const Components = @import("../Components.zig");
const TransformComponent = Components.TransformComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const CircleRenderComponent = Components.CircleRenderComponent;

mSpriteEntities: std.ArrayList(u32),
mCircleEntities: std.ArrayList(u32),

pub fn Init(allocator: std.mem.Allocator) RenderSystem {
    return RenderSystem{
        .mSpriteEntities = std.ArrayList(u32).init(allocator),
        .mCircleEntities = std.ArrayList(u32).init(allocator),
    };
}

pub fn Deinit(self: RenderSystem) void {
    self.mSpriteEntities.deinit();
    self.mCircleEntities.deinit();
}

pub fn Update(self: RenderSystem, component_manager: ComponentManager) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //culling
    const end_index_sprites = self.CullShouldRender(component_manager, SpriteRenderComponent, allocator);
    const end_index_circles = self.CullShouldRender(component_manager, CircleRenderComponent, allocator);

    //other optimization passes

    //final resulting list to draw
    for (0..end_index_sprites) |i| {
        const entity_id = self.mSpriteEntities.items[i];
        const transform_component = component_manager.GetComponent(TransformComponent, entity_id);
        if (component_manager.HasComponent(SpriteRenderComponent, entity_id) == true) {
            const sprite_render_component = component_manager.GetComponent(SpriteRenderComponent, entity_id);
            RenderManager.DrawSprite(transform_component.GetTransformMatrix(), sprite_render_component.mColor, 0, sprite_render_component.mTilingFactor); //TODO: change texture index to actual texture index
            //TODO: just keeping texture index 0 for now because I havnt added the texture list or anything yet to this render sytstem
        } else if (component_manager.HasComponent(CircleRenderComponent, entity_id) == true) {
            const circle_render_component = component_manager.GetComponent(CircleRenderComponent, entity_id);
            RenderManager.DrawCircle(transform_component.GetTransformMatrix(), circle_render_component.mColor, circle_render_component.mThickness, circle_render_component.mFade);
        }
    }

    //circles
    for (0..end_index_circles) |i| {
        const entity_id = self.mCircleEntities.items[i];
        const transform_component = component_manager.GetComponent(TransformComponent, entity_id);
        if (component_manager.HasComponent(SpriteRenderComponent, entity_id) == true) {
            const sprite_render_component = component_manager.GetComponent(SpriteRenderComponent, entity_id);
            RenderManager.DrawSprite(transform_component.GetTransformMatrix(), sprite_render_component.mColor, 0, sprite_render_component.mTilingFactor); //TODO: change texture index to actual texture index
            //TODO: just keeping texture index 0 for now because I havnt added the texture list or anything yet to this render sytstem
        } else if (component_manager.HasComponent(CircleRenderComponent, entity_id) == true) {
            const circle_render_component = component_manager.GetComponent(CircleRenderComponent, entity_id);
            RenderManager.DrawCircle(transform_component.GetTransformMatrix(), circle_render_component.mColor, circle_render_component.mThickness, circle_render_component.mFade);
        }
    }
}

pub const Ind: usize = blk: {
    for (SystemsList, 0..) |system_type, i| {
        if (system_type == RenderSystem) {
            break :blk i;
        }
    }
};

fn CullShouldRender(self: RenderSystem, component_manager: ComponentManager, component_type: type) usize {
    const entity_list = if (component_type == SpriteRenderComponent) self.mSpriteEntities else self.mCircleEntities;
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
