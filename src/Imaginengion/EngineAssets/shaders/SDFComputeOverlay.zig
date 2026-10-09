const std = @import("std");
const SDFShared = @import("SDFSharedData.zig");
const spirv = std.spirv;

const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Vec4 = @import("IM").Vec4;
const CameraRay = @import("IM").CameraRay;
const RayMarcherFn = @import("IM").RayMarcher;
const Node = @import("IM").Node;
const Edge = @import("IM").Edge;

const CameraUBO = SDFShared.CameraUBO;
const ShapesSSBO = SDFShared.ShapesSSBO;
const ShapeSurfacesSSBO = SDFShared.ShapeSurfacesSSBO;
const BVHNodesSSBO = SDFShared.BVHNodesSSBO;
const ClipsSSBO = SDFShared.ClipsSSBO;
const SurfShadingSSBO = SDFShared.SurfShadingSSBO;
const MedShadingSSBO = SDFShared.MedShadingSSBO;
const OutTexture = SDFShared.OutTexture;
const TexturesArray = SDFShared.TexturesArray;

const PushConstants = @import("IM").PushConstants;
//kept a constant rather than picked per pass: a ray that hits nothing ends on nothing, so the shader compiler folds that
//case away for every pixel. The game's background goes under at the end instead (FLAG_GAME_BACKGROUND)
const background: Vec4(f32) = .FromArray(PushConstants.OVERLAY_BACKGROUND);

const OverlayRayMarcher = RayMarcherFn(
    @TypeOf(&ShapesSSBO.ptr),
    @TypeOf(&ShapeSurfacesSSBO.ptr),
    @TypeOf(&BVHNodesSSBO.ptr),
    @TypeOf(&ClipsSSBO.ptr),
    @TypeOf(&SurfShadingSSBO.ptr),
    @TypeOf(&MedShadingSSBO.ptr),
    @TypeOf(TexturesArray),
    .BVH,
);

export fn main() callconv(.{ .spirv_kernel = .{ .x = 8, .y = 8, .z = 1 } }) void {
    const global = spirv.global_invocation_id;
    if (@as(f32, @floatFromInt(global[0])) >= CameraUBO.mViewportWidth or @as(f32, @floatFromInt(global[1])) >= CameraUBO.mViewportHeight) return;

    //the pixel center, CameraRay takes continuous pixel coordinates
    const pixel = Vec2(f32){ .x = @as(f32, @floatFromInt(global[0])) + 0.5, .y = @as(f32, @floatFromInt(global[1])) + 0.5 };
    const ray_params = CameraRay.RayParams{ .Scale = .FromVector(CameraUBO.mRayScale), .Offset = .FromVector(CameraUBO.mRayOffset) };
    const ray = CameraRay.MakeRay(.{ .Position = .FromVector(CameraUBO.mPosition), .Rotation = .FromVector(CameraUBO.mRotation) }, ray_params, pixel);

    var marcher = OverlayRayMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
        .mDefaultColor = background,
        .mShapes = &ShapesSSBO.ptr,
        .mShapeSurfaces = &ShapeSurfacesSSBO.ptr,
        .mShapesCount = CameraUBO.mShapesCount,
        .mDirectCount = CameraUBO.mDirectCount,
        .mBVHNodes = &BVHNodesSSBO.ptr,
        .mClips = &ClipsSSBO.ptr,
        .mSurfShading = &SurfShadingSSBO.ptr,
        .mMedShading = &MedShadingSSBO.ptr,
        .mPerspectiveFar = CameraUBO.mPerspectiveFar,
    };

    //setup initial node and edge
    marcher.mNodes[0] = Node{
        .Point = ray.Origin,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = OverlayRayMarcher.NO_EDGE,
        .FirstEdge = OverlayRayMarcher.NO_EDGE,
        .MaterialHandle = 0,
        .AccumColor = background,
        .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
        .ShapeT = .None,
    };
    marcher.mNodeCount = 1;

    marcher.mEdges[0] = Edge{
        .Direction = ray.Dir,
        .Length = 0.0,
        .FromNode = 0,
        .ToNode = 0,
        .SiblingEdge = OverlayRayMarcher.NO_EDGE,
        .AccumColor = background,
        .MaterialHandle = 0,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    marcher.March(SDFShared.imageSampleExplicitLod, TexturesArray);

    //traverse ray tree backwards to obtain final output color
    const overlay_color = marcher.GenerateColor(SDFShared.imageSampleExplicitLod, TexturesArray);
    //the game layer has nothing in it this render, so its pass is skipped and this puts its background under instead
    const final_color = if (CameraUBO.mFlags & PushConstants.FLAG_GAME_BACKGROUND != 0)
        SDFShared.Over(overlay_color, .FromArray(PushConstants.GAME_BACKGROUND))
    else
        overlay_color;

    std.spirv.imageWrite(OutTexture, u32, .{ global[0], global[1] }, final_color.ToVector());
}
