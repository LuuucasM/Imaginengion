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
const MasksSSBO = SDFShared.MasksSSBO;
const ProgramInstrsSSBO = SDFShared.ProgramInstrsSSBO;
const ProgramPartsSSBO = SDFShared.ProgramPartsSSBO;
const SurfShadingSSBO = SDFShared.SurfShadingSSBO;
const MedShadingSSBO = SDFShared.MedShadingSSBO;
const OutTexture = SDFShared.OutTexture;
const TexturesArray = SDFShared.TexturesArray;

const imageRead = SDFShared.imageRead;

const PushConstants = @import("IM").PushConstants;
const background: Vec4(f32) = .FromArray(PushConstants.GAME_BACKGROUND);

const GameRayMarcher = RayMarcherFn(
    @TypeOf(&ShapesSSBO.ptr),
    @TypeOf(&ShapeSurfacesSSBO.ptr),
    @TypeOf(&BVHNodesSSBO.ptr),
    @TypeOf(&MasksSSBO.ptr),
    @TypeOf(&ProgramInstrsSSBO.ptr),
    @TypeOf(&ProgramPartsSSBO.ptr),
    @TypeOf(&SurfShadingSSBO.ptr),
    @TypeOf(&MedShadingSSBO.ptr),
    @TypeOf(TexturesArray),
    .BVH,
);

export fn main() callconv(.{ .spirv_kernel = .{ .x = 8, .y = 8, .z = 1 } }) void {
    const global = spirv.global_invocation_id;
    if (@as(f32, @floatFromInt(global[0])) >= CameraUBO.mViewportWidth or @as(f32, @floatFromInt(global[1])) >= CameraUBO.mViewportHeight) return;

    //what the overlay pass drew here, which this goes under. Without an overlay pass this render the texture holds
    //nothing of this frame, so there is nothing above
    const sample: Vec4(f32) = if (CameraUBO.mFlags & PushConstants.FLAG_UNDER_OVERLAY != 0)
        .FromVector(imageRead(OutTexture, u32, .{ global[0], global[1] }))
    else
        .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    if (sample.w >= 0.999) return;

    //the pixel center, CameraRay takes continuous pixel coordinates
    const pixel = Vec2(f32){ .x = @as(f32, @floatFromInt(global[0])) + 0.5, .y = @as(f32, @floatFromInt(global[1])) + 0.5 };
    const ray_params = CameraRay.RayParams{ .Scale = .FromVector(CameraUBO.mRayScale), .Offset = .FromVector(CameraUBO.mRayOffset) };
    const ray = CameraRay.MakeRay(.{ .Position = .FromVector(CameraUBO.mPosition), .Rotation = .FromVector(CameraUBO.mRotation) }, ray_params, pixel);

    var marcher = GameRayMarcher{
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
        .mMasks = &MasksSSBO.ptr,
        .mInstrs = &ProgramInstrsSSBO.ptr,
        .mParts = &ProgramPartsSSBO.ptr,
        .mSurfShading = &SurfShadingSSBO.ptr,
        .mMedShading = &MedShadingSSBO.ptr,
        .mPerspectiveFar = CameraUBO.mPerspectiveFar,
    };

    //setup initial node and edge
    marcher.mNodes[0] = Node{
        .Point = ray.Origin,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = GameRayMarcher.NO_EDGE,
        .FirstEdge = GameRayMarcher.NO_EDGE,
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
        .SiblingEdge = GameRayMarcher.NO_EDGE,
        .AccumColor = background,
        .MaterialHandle = 0,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    marcher.March(SDFShared.imageSampleExplicitLod, TexturesArray);

    //traverse ray tree backwards to obtain final output color
    const march_color = marcher.GenerateColor(SDFShared.imageSampleExplicitLod, TexturesArray);

    //the overlay over the game
    const final_color = SDFShared.Over(sample, march_color);

    std.spirv.imageWrite(OutTexture, u32, .{ global[0], global[1] }, final_color.ToVector());
}
