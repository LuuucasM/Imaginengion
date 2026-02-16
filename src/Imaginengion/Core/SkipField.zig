//! Provides a skip field data structure for tracking active/inactive indices.
//!
//! This module defines a generic `StaticSkipField(size)` type which efficiently marks and manages
//! skipped (inactive) and unskipped (active) elements within a fixed-size array.
//!
//! The skip field is particularly useful in scenarios such as:
//! - Component pools in ECS systems where components may be dynamically removed and re-added.
//! - Sparse memory management schemes.
//! - Custom allocators or free lists for small object reuse.
//!
//! The API supports:
//! - Initializing the field in either a fully skipped or unskipped state.
//! - Marking individual elements as skipped or unskipped.
//! - Merging and splitting skip spans to maintain compact ranges.
//!
//! Internally, it uses a simple linear encoding to store skip run lengths, allowing O(1) operations
//! in most common cases.
const std = @import("std");

/// Creates a static skip field structure of a fixed size.
/// This can be used to efficiently track and modify "skipped" elements,
/// similar to a free-list or block allocation system.
///
/// Parameters:
/// - `size`: The fixed size of the skip field.
///
/// Returns:
/// - A struct type for a specific sized static skipfield, with methods to initialize, reset, and toggle skipped states for indices.
pub fn StaticSkipField(size: usize) type {
    return struct {
        const Self = @This();
        pub const SkipFieldType = std.math.IntFittingRange(0, size);
        const AllSkipArr: [size]SkipFieldType = AllSkipFn(size, SkipFieldType);
        const NoSkipArr: [size]SkipFieldType = std.mem.zeroes([size]SkipFieldType);

        const InitOption = enum(u1) {
            AllSkip = 0,
            NoSkip = 1,
        };

        const FieldIterator = struct {
            mSkipFieldRef: *Self,
            mI: usize,

            pub fn Next(self: *FieldIterator) ?usize {
                if (self.mI >= self.mSkipFieldRef.mSkipField.len) return null;

                const current_index = self.mI;

                self.mI += 1;
                self.mI += self.mSkipFieldRef.mSkipField[self.mI];

                return current_index;
            }
        };

        mSkipField: [size]SkipFieldType = NoSkipArr,

        /// Initializes a new skip field instance with the given option.
        ///
        /// Parameters:
        /// - `option`: Whether to set the field to "all skipped" or "none skipped" for initialization.
        ///
        /// Returns:
        /// - A new `Self` instance with its skip field initialized accordingly.
        pub fn Init(option: InitOption) Self {
            var new_skipfield = Self{};
            if (option == .AllSkip) new_skipfield.Reset(option);
            return new_skipfield;
        }

        /// Resets the skip field based on the specified option.
        ///
        /// Parameters:
        /// - `option`: If `AllSkip`, all indices are marked as skipped.
        ///             If `NoSkip`, all indices are marked as unskipped.
        /// Returns:
        ///  - Nothing
        pub fn Reset(self: *Self, option: InitOption) void {
            if (option == .AllSkip) {
                self.mSkipField = AllSkipArr;
            } else { //NoSkip option
                self.mSkipField = NoSkipArr;
            }
        }

        pub fn Iterator(self: *Self) FieldIterator {
            return FieldIterator{
                .mSkipFieldRef = self,
                .mI = self.mSkipField[0],
            };
        }

        /// Marks the element at the specified index as skipped.
        ///
        /// Parameters:
        /// - `index`: The index to mark as skipped.
        ///
        /// Notes:
        /// - Skipping is only applied if the index is currently unskipped.
        /// - This function coalesces adjacent skipped ranges.
        ///
        /// Returns:
        /// - Nothing
        pub fn ChangeToSkipped(self: *Self, index: SkipFieldType) void {
            std.debug.assert(self.mSkipField.len > index);
            if (size < 2) {
                self.mSkipField[0] = 1;
                return;
            }
            //alreday a skipped index
            if (self.mSkipField[index] != 0) return;

            const left_non_zero = index > 0 and self.mSkipField[index - 1] > 0;
            const right_non_zero = index < size - 1 and self.mSkipField[index + 1] > 0;

            //left and right are zero
            if (!left_non_zero and !right_non_zero) {
                self.mSkipField[index] = 1;
            }
            //only left is non-zero
            else if (left_non_zero and !right_non_zero) {
                const left_val = self.mSkipField[index - 1];
                const new_value = left_val + 1;
                self.mSkipField[index] = new_value;
                self.mSkipField[index - left_val] = new_value;
            }
            //only right is non-zero
            else if (!left_non_zero and right_non_zero) {
                const right_val = self.mSkipField[index + 1];
                const new_value = right_val + 1;
                self.mSkipField[index] = new_value;
                self.mSkipField[index + right_val] = new_value;
            }
            //both left and right are non-zero
            else {
                const left_val = self.mSkipField[index - 1];
                const right_val = self.mSkipField[index + 1];
                const new_value = left_val + right_val + 1;
                self.mSkipField[index - left_val] = new_value;
                self.mSkipField[index + right_val] = new_value;
                self.mSkipField[index] = 1;
            }
        }

        /// Marks the element at the specified index as unskipped.
        ///
        /// Parameters:
        /// - `index`: The index to mark as unskipped.
        ///
        /// Notes:
        /// - Unskipping splits or shrinks adjacent skip ranges.
        ///
        /// Returns:
        /// - Nothing
        pub fn ChangeToUnskipped(self: *Self, index: SkipFieldType) void {
            std.debug.assert(self.mSkipField.len > index);
            if (size < 2) {
                self.mSkipField[0] = 0;
                return;
            }
            //alreday a skipped index
            if (self.mSkipField[index] == 0) return;

            const left_non_zero = index > 0 and self.mSkipField[index - 1] > 0;
            const right_non_zero = index < size - 1 and self.mSkipField[index + 1] > 0;

            //left and right are zero
            if (!left_non_zero and !right_non_zero) {
                //we dont have to do anything because we will make it 0 at the end anyway
            }
            //only left is non-zero
            else if (left_non_zero and !right_non_zero) {
                const new_value = self.mSkipField[index] - 1;
                self.mSkipField[index - new_value] = new_value;
                self.mSkipField[index - 1] = new_value;
            }
            //only right is non-zero
            else if (!left_non_zero and right_non_zero) {
                const new_value = self.mSkipField[index] - 1;
                self.mSkipField[index + new_value] = new_value;
                self.mSkipField[index + 1] = new_value;
            }
            //both left and right are non-zero
            else {
                var start_ind = index;
                while (start_ind > 0 and self.mSkipField[start_ind - 1] != 0) : (start_ind -= 1) {}

                var end_ind = index;
                while (end_ind < size - 1 and self.mSkipField[end_ind + 1] != 0) : (end_ind += 1) {}

                const left_len = index - start_ind;
                const right_len = end_ind - index;

                self.mSkipField[start_ind] = left_len;
                self.mSkipField[index - 1] = left_len;

                self.mSkipField[index + 1] = right_len;
                self.mSkipField[end_ind] = right_len;
            }
            self.mSkipField[index] = 0;
        }
    };
}

fn AllSkipFn(comptime size: usize, comptime field_type: type) [size]field_type {
    var arr: [size]field_type = std.mem.zeroes([size]field_type);
    arr[0] = size;
    arr[size - 1] = size;
    return arr;
}

test "Init Small Field" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.AllSkip);
    try std.testing.expect(field.mSkipField[0] == FieldSize);

    field = SkipFieldT.Init(.NoSkip);
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To UnSkip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.AllSkip);
    try std.testing.expect(field.mSkipField[0] == 1);

    field.ChangeToUnskipped(0);
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To Skip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);
    try std.testing.expect(field.mSkipField[0] == 0);

    field.ChangeToSkipped(0);
    try std.testing.expect(field.mSkipField[0] == 1);
}

test "Init Large Field" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.AllSkip);
    try std.testing.expect(field.mSkipField[0] == FieldSize);
    try std.testing.expect(field.mSkipField[FieldSize - 1] == FieldSize);
    for (1..FieldSize - 2) |i| {
        try std.testing.expect(field.mSkipField[i] == 0);
    }

    field = SkipFieldT.Init(.NoSkip);
    for (field.mSkipField) |index| {
        try std.testing.expect(index == 0);
    }
}

test "Large Change To Skip" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);

    field.ChangeToSkipped(4);
    try std.testing.expect(field.mSkipField[4] == 1);

    field.ChangeToSkipped(0);
    try std.testing.expect(field.mSkipField[0] == 1);

    field.ChangeToSkipped(3);
    try std.testing.expect(field.mSkipField[3] == 2);
    try std.testing.expect(field.mSkipField[4] == 2);

    field.ChangeToSkipped(1);
    try std.testing.expect(field.mSkipField[0] == 2);
    try std.testing.expect(field.mSkipField[1] == 2);

    field.ChangeToSkipped(2);
    try std.testing.expect(field.mSkipField[0] == 5);
    try std.testing.expect(field.mSkipField[4] == 5);
    try std.testing.expect(field.mSkipField[2] == 1);
}

test "Large Change To UnSkip" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(0);
    field.ChangeToSkipped(3);
    field.ChangeToSkipped(1);
    field.ChangeToSkipped(2);

    field.ChangeToUnskipped(4);
    try std.testing.expect(field.mSkipField[0] == 4);
    try std.testing.expect(field.mSkipField[3] == 4);

    field.ChangeToUnskipped(0);
    try std.testing.expect(field.mSkipField[1] == 3);
    try std.testing.expect(field.mSkipField[3] == 3);

    field.ChangeToUnskipped(2);
    try std.testing.expect(field.mSkipField[1] == 1);
    try std.testing.expect(field.mSkipField[3] == 1);
}

test "Iterating Skipfield 1" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(0);

    var iter = field.Iterator();
    while (iter.Next()) |i| {
        try std.testing.expect(i == 1 or i == 2 or i == 3);
    }
}

test "Iterating Skipfield 2" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(3);

    var iter = field.Iterator();
    while (iter.Next()) |i| {
        try std.testing.expect(i == 0 or i == 1 or i == 2);
    }
}

test "Iterating Skipfield 3" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field = SkipFieldT.Init(.NoSkip);

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(2);
    field.ChangeToSkipped(3);

    var iter = field.Iterator();
    while (iter.Next()) |i| {
        try std.testing.expect(i == 0 or i == 1);
    }
}
