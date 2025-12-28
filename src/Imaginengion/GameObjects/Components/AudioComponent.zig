const std = @import("std");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetManager = @import("../../Assets/AssetManager.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const AudioAsset = @import("../../Assets/Assets/AudioAsset.zig").AudioAsset;
const Assets = @import("../../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const imgui = @import("../../Core/CImports.zig").imgui;
const Entity = @import("../Entity.zig");
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

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = true;

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

pub fn ReadFrames(self: *AudioComponent, frames_out: []f32, frame_count: u64) !u64 {
    const audio_asset = try self.mAudioAsset.GetAsset(AudioAsset);

    return audio_asset.ReadFrames(frames_out, frame_count, *self.mCursor, self.mLoop);
}

pub fn Deinit(self: *AudioComponent) !void {
    if (self.mAudioAsset.mID != AssetHandle.NullHandle) {
        AssetManager.ReleaseAssetHandleRef(&self.mAudioAsset);
    }
}

pub fn GetName(_: AudioComponent) []const u8 {
    return "AudioComponent";
}

pub fn GetInd(_: AudioComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AudioComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn EditorRender(self: *AudioComponent, frame_allocator: std.mem.Allocator) !void {
    // Volume drag
    _ = imgui.igDragFloat("Volume", &self.mVolume, 0.01, 0.0, 1.0, "%.2f", imgui.ImGuiSliderFlags_None);

    // Pitch drag
    _ = imgui.igDragFloat("Pitch", &self.mPitch, 0.01, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);

    // Loop toggle
    _ = imgui.igCheckbox("Loop", &self.mLoop);

    // Audio type dropdown
    const audio_type_names = [_][]const u8{ "2D", "3D" };
    var current_audio_type: i32 = @intFromEnum(self.mAudioType);
    const preview_text: []const u8 = audio_type_names[@as(usize, @intCast(current_audio_type))];
    var preview_buf: [16]u8 = undefined;
    const preview_cstr = try std.fmt.bufPrintZ(&preview_buf, "{s}", .{preview_text});

    if (imgui.igBeginCombo("Audio Type", @ptrCast(preview_cstr.ptr), imgui.ImGuiComboFlags_None)) {
        defer imgui.igEndCombo();

        for (audio_type_names, 0..) |name, i| {
            var name_buf: [16]u8 = undefined;
            const name_cstr = try std.fmt.bufPrintZ(&name_buf, "{s}", .{name});
            const is_selected = (current_audio_type == @as(i32, @intCast(i)));
            if (imgui.igSelectable_Bool(name_cstr.ptr, is_selected, 0, .{ .x = 0, .y = 0 })) {
                current_audio_type = @as(i32, @intCast(i));
                self.mAudioType = @enumFromInt(@as(u8, @intCast(current_audio_type)));
            }
            if (is_selected) {
                imgui.igSetItemDefaultFocus();
            }
        }
    }

    // Audio asset display with drag-drop target
    imgui.igSeparator();
    if (self.mAudioAsset.mID != AssetHandle.NullHandle) {
        const file_data_asset = try self.mAudioAsset.GetAsset(FileMetaData);
        const name = std.fs.path.stem(std.fs.path.basename(file_data_asset.mRelPath.items));
        const name_term = try frame_allocator.dupeZ(u8, name);
        imgui.igTextUnformatted("Audio Asset: ", null);
        imgui.igSameLine(0.0, 0.0);
        imgui.igTextUnformatted(name_term, null);
    } else {
        imgui.igTextUnformatted("Audio Asset: None", null);
    }

    if (imgui.igBeginDragDropTarget()) {
        if (imgui.igAcceptDragDropPayload("MP3Load", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            AssetManager.ReleaseAssetHandleRef(&self.mAudioAsset);
            self.mAudioAsset = try AssetManager.GetAssetHandleRef(path, .Prj);
        }
        imgui.igEndDragDropTarget();
    }
}
