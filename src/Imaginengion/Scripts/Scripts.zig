pub const AnimationScript = @import("scripts/AnimationScript.zig");
pub const CollisionScript = @import("scripts/CollisionScript.zig");
pub const EntityScript = @import("scripts/EntityScript.zig");
pub const PostInputScript = @import("scripts/PostInputScript.zig");

pub const ComponentsList = [_]type{
    AnimationScript,
    CollisionScript,
    EntityScript,
    PostInputScript,
};

pub const EComponents = enum(usize) {
    AnimationScript = AnimationScript.Ind,
    CollisionScript = CollisionScript.Ind,
    EntityScript = EntityScript.Ind,
    PostInputScript = PostInputScript.Ind,
};
