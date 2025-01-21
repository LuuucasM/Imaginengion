const std = @import("std");
const SystemsList = @import("../Systems.zig").SystemsList;
const ComponentManager = @import("../../ECS/ComponentManager.zig");
const RenderManager = @import("../../Renderer/Renderer.zig");
const RenderSystem = @This();

const Components = @import("../Components.zig");
const TransformComponent = Components.TransformComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const CircleRenderComponent = Components.CircleRenderComponent;

mEntityList: std.ArrayList(u32),

pub fn Init(allocator: std.mem.Allocator) RenderSystem {
    return RenderSystem{
        .mEntityList = std.ArrayList(u32).init(allocator),
    };
}

pub fn Deinit(self: RenderSystem) void {
    self.mEntityList.deinit();
}

pub fn Update(self: RenderSystem, component_manager: ComponentManager) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    //culling
    const cull_should_render = CullShouldRender(component_manager, self.mEntityList, allocator);

    //other optimization passes?

    //final resulting list to draw
    for (cull_should_render.items) |entity_id| {
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

    cull_should_render.deinit();
}

pub const Ind: usize = blk: {
    for (SystemsList, 0..) |system_type, i| {
        if (system_type == RenderSystem) {
            break :blk i;
        }
    }
};

fn CullShouldRender(component_manager: ComponentManager, entity_list: std.ArrayList(u32), allocator: std.mem.Allocator) std.ArrayList(u32) {
    const new_entity_list = std.ArrayList(u32).init(allocator);
    for (entity_list.items) |entity_id| {
        if (component_manager.HasComponent(SpriteRenderComponent, entity_id) == true) {
            const sprite_render_component = component_manager.GetComponent(SpriteRenderComponent, entity_id);
            if (sprite_render_component.mShouldRender == true) {
                new_entity_list.append(entity_id);
            }
        }
        if (component_manager.HasComponent(CircleRenderComponent, entity_id) == true) {
            const circle_render_component = component_manager.GetComponent(CircleRenderComponent, entity_id);
            if (circle_render_component.mShouldRender == true) {
                new_entity_list.append(entity_id);
            }
        }
    }
    return new_entity_list;
}
