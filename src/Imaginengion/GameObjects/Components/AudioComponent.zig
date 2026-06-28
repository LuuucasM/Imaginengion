const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const AudioAsset = @import("../../Assets/Assets/AudioAsset.zig").AudioAsset;
const Assets = @import("../../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const PathType = @import("../../Assets/AssetManager.zig").PathType;
const Entity = @import("../Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

const AudioComponent = @This();

pub const PlaybackState = enum(u8) {
    Ready = 0,
    Playing = 1,
    Paused = 2,
    Finished = 3,
};

pub const AudioType = enum(u8) {
    Audio2D = 0,
    Audio3D = 1,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "AudioComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AudioComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mAudioType: AudioType = .Audio2D,
mPlaybackState: PlaybackState = .Ready,
mAudioAsset: AssetHandle = .{},
mCursor: u64 = 0,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,

pub fn ReadFrames(self: *AudioComponent, engine_context: EngineContext, frames_out: []f32, frame_count: u64) !u64 {
    const audio_asset = try self.mAudioAsset.GetAsset(engine_context, AudioAsset);

    return audio_asset.ReadFrames(frames_out, frame_count, *self.mCursor, self.mLoop);
}

pub fn Deinit(self: *AudioComponent, _: *EngineContext) !void {
    self.mAudioAsset.ReleaseAsset();
}
pub fn EditorRender(self: *AudioComponent, engine_context: *EngineContext) !void {
    // Volume drag
    _ = ImguiManager.RenderFloatDrag(&self.mVolume, "Volume", 0.01, 0.0, 1.0);

    // Pitch drag
    _ = ImguiManager.RenderFloatDrag(&self.mPitch, "Pitch", 0.01, 0.0, 0.0); //0.0 for upper bounds means no upper bounds i believe

    // Loop toggle
    ImguiManager.RenderBool(&self.mLoop, "Looping?");

    ImguiManager.RenderEnum(AudioType, &self.mAudioType, "Audio Type");

    ImguiManager.ImguiSeparator();

    try ImguiManager.RenderAssetRef(engine_context, &self.mAudioAsset, "Audio Asset", "AudioAsset");
}

pub fn jsonStringify(self: *const AudioComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("AudioType");
    try jw.write(self.mAudioType);

    try jw.objectField("FilePath");
    const asset_file_data = self.mAudioAsset.GetFileMetaData();
    try jw.write(asset_file_data.mRelPath.items);

    try jw.objectField("PathType");
    try jw.write(asset_file_data.mPathType);

    try jw.objectField("Volume");
    try jw.write(self.mVolume);

    try jw.objectField("Pitch");
    try jw.write(self.mPitch);

    try jw.objectField("Loop");
    try jw.write(self.mLoop);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!AudioComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: AudioComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "AudioType")) {
            result.mAudioType = try std.json.innerParse(AudioType, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "FilePath")) {
            const parsed_path = try std.json.innerParse([]const u8, frame_allocator, reader, options);

            try SkipToken(reader); //skip PathType object field

            const parsed_path_type = try std.json.innerParse(PathType, frame_allocator, reader, options);

            result.mAudioAsset = engine_context.mAssetManager.GetAssetHandleRef(
                engine_context,
                .{ .File = .{ .rel_path = parsed_path, .path_type = parsed_path_type } },
            ) catch |err| {
                std.debug.panic("error: {}\n", .{err});
            };
        } else if (std.mem.eql(u8, field_name, "Volume")) {
            result.mVolume = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Pitch")) {
            result.mPitch = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Loop")) {
            result.mLoop = try std.json.innerParse(bool, frame_allocator, reader, options);
        }
    }

    return result;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
