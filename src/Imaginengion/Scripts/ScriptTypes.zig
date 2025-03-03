pub const AnimationScript = @import("ScriptTypes/AnimationScript.zig");
pub const CollisionScript = @import("ScriptTypes/CollisionScript.zig");
pub const EntityScript = @import("ScriptTypes/EntitiyScript.zig");
pub const PostInputScript = @import("ScriptTypes/PostInputScript.zig");

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
