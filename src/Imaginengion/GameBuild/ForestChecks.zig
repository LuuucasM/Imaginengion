//! The checks run over the forest ProjectWalk builds: what's saved on objects against what their scripts declare, and
//! what's saved as a UUID against the objects there are. They only read the forest and say what's wrong: what's saved stays
//! as it is, and so does what gets built.
//! Only std, like ProjectWalk.
const std = @import("std");
const ProjectWalk = @import("ProjectWalk.zig");

const FileId = ProjectWalk.FileId;
const ObjectLink = ProjectWalk.ObjectLink;
const ObjectNode = ProjectWalk.ObjectNode;
const Result = ProjectWalk.Result;
const ScriptFile = ProjectWalk.ScriptFile;
const ScriptUse = ProjectWalk.ScriptUse;

pub const Checks = struct {
    /// each one a line of the report saying what's wrong and where
    mProblems: std.ArrayList([]const u8) = .empty,
};

/// Everything wrong in `result`, in order of its files. Memory from `arena`
pub fn Run(arena: std.mem.Allocator, result: *const Result) !Checks {
    var checker: Checker = .{ .mArena = arena, .mResult = result };
    for (result.mObjectFiles.items) |*file| try checker.CheckObject(file.mFile, &file.mObject);
    for (std.enums.values(ProjectWalk.FileRoot)) |root| {
        var iter = result.mScriptFiles.getPtrConst(root).iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.mSyntaxErrors > 0) {
                try checker.Add(.{ .mRoot = root, .mPath = entry.key_ptr.* }, "has syntax errors", .{});
            }
        }
    }
    return checker.mChecks;
}

const Checker = struct {
    mArena: std.mem.Allocator,
    mResult: *const Result,
    mChecks: Checks = .{},

    fn Add(self: *Checker, file: FileId, comptime format: []const u8, args: anytype) !void {
        var text: std.Io.Writer.Allocating = .init(self.mArena);
        try ProjectWalk.WriteFileId(&text.writer, file);
        try text.writer.writeAll(": ");
        try text.writer.print(format, args);
        try self.mChecks.mProblems.append(self.mArena, text.written());
    }

    fn CheckObject(self: *Checker, file: FileId, object: *const ObjectNode) anyerror!void {
        for (object.mLinks.items) |*link| try self.CheckLink(file, object, "", link);
        for (object.mScripts.items) |*use| try self.CheckScript(file, object, use);
        for (object.mChildren.items) |*child| try self.CheckObject(file, child);
    }

    /// A script's file that isn't there is already in the report's Missing, with nothing to check it against
    fn CheckScript(self: *Checker, file: FileId, object: *const ObjectNode, use: *const ScriptUse) !void {
        const script = self.mResult.mScriptFiles.getPtrConst(use.mFile.mRoot).getPtr(use.mFile.mPath) orelse return;
        const script_name = std.fs.path.basename(use.mFile.mPath);

        if (script.mOwner) |owner| {
            //the engine skips a script's hooks on any other type of object (ScriptsProcessor.RunHook)
            if (owner != object.mKind) {
                try self.Add(file, "{s} \"{s}\" has {s}, whose hooks are for {s}", .{ @tagName(object.mKind), object.mName, script_name, @tagName(owner) });
            }
        } else {
            try self.Add(file, "\"{s}\" has {s}, which has no hooks or event handlers", .{ object.mName, script_name });
        }

        for (script.mVariables.items) |variable| {
            const wants = variable.mFileRef orelse continue;
            const saved_file = if (use.mValues) |values| SavedFile(values.get(variable.mName)) else null;
            if (saved_file) |saved| {
                if (ProjectWalk.ObjectKindOfFile(saved.mPath) != wants) {
                    try self.Add(file, "\"{s}\" {s}: {s} ({s}) names {s}, which isn't that kind of file", .{ object.mName, script_name, variable.mName, variable.mType, saved.mPath });
                }
            } else {
                try self.Add(file, "\"{s}\" {s}: {s} ({s}) has no file set", .{ object.mName, script_name, variable.mName, variable.mType });
            }
        }

        if (use.mValues) |values| {
            var iter = values.iterator();
            while (iter.next()) |entry| {
                if (script.GetVariable(entry.key_ptr.*) == null) {
                    try self.Add(file, "\"{s}\" {s}: saves {s}, which the script no longer has", .{ object.mName, script_name, entry.key_ptr.* });
                }
            }
        }

        for (use.mLinks.items) |*link| try self.CheckLink(file, object, script_name, link);
    }

    /// `script_name` is empty for a component's link
    fn CheckLink(self: *Checker, file: FileId, object: *const ObjectNode, script_name: []const u8, link: *const ObjectLink) !void {
        const separator = if (script_name.len > 0) ": " else "";
        const target = link.mTarget orelse {
            return self.Add(file, "\"{s}\" {s}{s}{s} wants {s} {d}, which no needed file has", .{ object.mName, script_name, separator, link.mField, @tagName(link.mWants), link.mUUID });
        };
        if (target.mKind != link.mWants) {
            try self.Add(file, "\"{s}\" {s}{s}{s} wants {s}, but {d} is the {s} \"{s}\" in {s}", .{
                object.mName,
                script_name,
                separator,
                link.mField,
                @tagName(link.mWants),
                link.mUUID,
                @tagName(target.mKind),
                target.mName,
                target.mFile.mPath,
            });
        }
    }
};

/// The file a file ref variable saved `value` has, null if it has none
fn SavedFile(value: ?std.json.Value) ?FileId {
    const saved = value orelse return null;
    if (saved != .object) return null;
    const file = saved.object.get("File") orelse return null;
    if (file != .object) return null;
    return ProjectWalk.FileRefOf(file.object, null);
}

/// The end of the report: what the checks found
pub fn WriteChecks(out: *std.Io.Writer, checks: *const Checks) !void {
    if (checks.mProblems.items.len == 0) {
        try out.writeAll("Problems: none\n");
        return;
    }
    try out.print("Problems ({d}):\n", .{checks.mProblems.items.len});
    for (checks.mProblems.items) |problem| try out.print("  {s}\n", .{problem});
}
