const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;

const Entity = @import("../GameObjects/Entity.zig");

pub const RayHit = struct {
    Hit: bool, //Was there a hit or not
    Distance: f32, //how far the hit object is from the origin
    Position: Vec3f32,
    Normal: Vec3f32,
    Entity: Entity,
    Collider: Entity, //optional depending on if we are tracing render objects or physics objects
};
