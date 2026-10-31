//! How game code moves a body, by the type of body it is: Dyn for a dynamic one, Kin for a kinematic one. They are the
//! RigidBodyComponent's own helpers reached from the entity, grouped so a type only lists what moves it. A static body
//! has no group, it never moves. They don't check the body's type, so what one does on the other type is what its
//! RigidBodyComponent helper does there. They do nothing on an entity with no rigid body.
const Entity = @import("../ECSObjects/Entity.zig");
const RigidBodyComponent = @import("../ECSComponents/EComponents.zig").RigidBodyComponent;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

//what moves both types, named in each of them
const Shared = struct {
    fn SetVelocity(entity: Entity, velocity: Vec3(f32)) void {
        const rigid_body = entity.GetComponentMut(RigidBodyComponent) orelse return;
        rigid_body.SetVelocity(velocity);
    }

    fn AddVelocity(entity: Entity, velocity: Vec3(f32)) void {
        const rigid_body = entity.GetComponentMut(RigidBodyComponent) orelse return;
        rigid_body.AddVelocity(velocity);
    }

    /// null on an entity with no rigid body
    fn GetVelocity(entity: Entity) ?Vec3(f32) {
        const rigid_body = entity.GetComponent(RigidBodyComponent) orelse return null;
        return rigid_body.GetVelocity();
    }
};

/// A dynamic body: moved by forces, gravity and its velocity, and pushed by what it hits
pub const Dyn = struct {
    pub const SetVelocity = Shared.SetVelocity;
    pub const AddVelocity = Shared.AddVelocity;
    pub const GetVelocity = Shared.GetVelocity;

    /// See RigidBodyComponent.ApplyForce: it pushes for one physics step
    pub fn ApplyForce(entity: Entity, force: Vec3(f32)) void {
        const rigid_body = entity.GetComponentMut(RigidBodyComponent) orelse return;
        rigid_body.ApplyForce(force);
    }

    /// See RigidBodyComponent.ApplyImpulse
    pub fn ApplyImpulse(entity: Entity, impulse: Vec3(f32)) void {
        const rigid_body = entity.GetComponentMut(RigidBodyComponent) orelse return;
        rigid_body.ApplyImpulse(impulse);
    }
};

/// A kinematic body: moved by its velocity alone, which code sets. Nothing pushes it, and static and kinematic bodies
/// its collision filter blocks stop it
pub const Kin = struct {
    pub const SetVelocity = Shared.SetVelocity;
    pub const AddVelocity = Shared.AddVelocity;
    pub const GetVelocity = Shared.GetVelocity;

    /// See RigidBodyComponent.MoveTo: it arrives by the end of the next physics step, then stops
    pub fn MoveTo(entity: Entity, target: Vec3(f32)) void {
        const rigid_body = entity.GetComponentMut(RigidBodyComponent) orelse return;
        rigid_body.MoveTo(target);
    }
};
