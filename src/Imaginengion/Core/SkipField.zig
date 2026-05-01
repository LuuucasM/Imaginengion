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
        pub const SkipFieldSize = size;
        pub const SkipFieldType = std.math.IntFittingRange(0, size);
        pub const SkipFieldVectorT = @Vector(size, SkipFieldType);
        pub const SkipFieldArrayT = [size]SkipFieldType;
        pub const AllSkipArr: SkipFieldArrayT = AllSkipFn(size, SkipFieldType);
        pub const NoSkipArr: SkipFieldArrayT = std.mem.zeroes(SkipFieldArrayT);

        pub const AllSkip: Self = .{ .mSkipField = AllSkipArr, .mNumUnskipped = 0 };
        pub const NoSkip: Self = .{ .mSkipField = NoSkipArr, .mNumUnskipped = size };

        const ResetOption = enum(u1) {
            AllSkip = 0,
            NoSkip = 1,
        };

        const FieldIterator = struct {
            mSkipFieldRef: *Self,
            mI: usize,

            pub fn next(self: *FieldIterator) ?usize {
                if (self.mI >= size) return null;

                const current_index = self.mI;

                self.mI += 1;
                self.mI += self.mSkipFieldRef.mSkipField[self.mI];

                return current_index;
            }
        };

        mSkipField: SkipFieldArrayT = AllSkipArr,
        mNumUnskipped: usize = 0,

        /// Resets the skip field based on the specified option.
        ///
        /// Parameters:
        /// - `option`: If `AllSkip`, all indices are marked as skipped.
        ///             If `NoSkip`, all indices are marked as unskipped.
        /// Returns:
        ///  - Nothing
        pub fn Reset(self: *Self, option: ResetOption) void {
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
        pub fn ChangeToSkipped(self: *Self, in_index: anytype) void {
            _ValidateIndexType(@TypeOf(in_index));
            std.debug.assert(size > in_index);

            const index: SkipFieldType = @intCast(in_index);

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

            self.mNumUnskipped -= 1;
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
        pub fn ChangeToUnskipped(self: *Self, in_index: anytype) void {
            _ValidateIndexType(@TypeOf(in_index));
            std.debug.assert(size > in_index);

            const index: SkipFieldType = @intCast(in_index);

            if (size < 2) {
                self.mSkipField[0] = 0;
                return;
            }
            //alreday an unskipped index
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
            self.mNumUnskipped += 1;
        }

        pub fn Union(self: *Self, other: *const Self) void {
            const zero_vec = @as(SkipFieldVectorT, @splat(0));
            const self_vec: Self.SkipFieldVectorT = self.mSkipField;
            const other_vec: Self.SkipFieldVectorT = other.mSkipField;

            const v1_zeros: @Vector(size, bool) = self_vec == zero_vec;
            const v2_zeros: @Vector(size, bool) = other_vec == zero_vec;

            const same_zeros: @Vector(size, bool) = v1_zeros == v2_zeros;

            const same_zeros_arr: [size]bool = same_zeros;

            for (0..size) |i| {
                if (!same_zeros_arr[i]) {
                    self.ChangeToSkipped(i);
                }
            }
        }

        pub fn Intersect(self: *Self, other: *const Self) void {
            const zero_vec = @as(SkipFieldVectorT, @splat(0));
            const self_vec: Self.SkipFieldVectorT = self.mSkipField;
            const other_vec: Self.SkipFieldVectorT = other.mSkipField;

            const v1_zeros: @Vector(size, bool) = self_vec == zero_vec;
            const v2_zeros: @Vector(size, bool) = other_vec == zero_vec;

            const same_zeros: @Vector(size, bool) = v1_zeros == v2_zeros;

            const same_zeros_arr: [size]bool = same_zeros;

            for (0..size) |i| {
                if (!same_zeros_arr[i]) {
                    self.ChangeToUnskipped(i);
                }
            }
        }

        pub fn Difference(self: *Self, other: *const Self) void {
            const zero_vec = @as(SkipFieldVectorT, @splat(0));
            const self_vec: Self.SkipFieldVectorT = self.mSkipField;
            const other_vec: Self.SkipFieldVectorT = other.mSkipField;

            const v1_zeros: @Vector(size, bool) = self_vec == zero_vec;
            const v2_zeros: @Vector(size, bool) = other_vec == zero_vec;

            const same_zeros: @Vector(size, bool) = v1_zeros == v2_zeros;

            const same_zeros_arr: [size]bool = same_zeros;

            for (0..size) |i| {
                if (same_zeros_arr[i]) {
                    self.ChangeToSkipped(i);
                }
            }
        }

        pub fn IndexIsUnskipped(self: Self, index: SkipFieldType) bool {
            return self.mSkipField[index] == 0;
        }

        pub fn HasSameUnskipped(self: Self, other: *const Self) bool {
            const zero_vec = @as(SkipFieldVectorT, @splat(0));

            const self_is_zeros = self.mSkipField == zero_vec;
            const other_is_zeros = other.mSkipField == zero_vec;

            const same_zeros = self_is_zeros == other_is_zeros;

            return @reduce(.And, same_zeros);
        }

        pub fn IsUnskippedSuperSet(self: Self, other: *const Self) bool {
            const zero_vec = @as(SkipFieldVectorT, @splat(0));

            const self_is_zeros = self.mSkipField == zero_vec;
            const other_is_zeros = other.mSkipField == zero_vec;

            const same_zeros = ~other_is_zeros | self_is_zeros;

            return @reduce(.And, same_zeros);
        }

        pub fn IsAllUnskipped(self: Self) bool {
            return self.mNumUnskipped == size;
        }

        pub fn GetFirstUnskipped(self: Self) ?usize {
            if (self.mSkipField[0] >= size) return null else return self.mSkipField[0];
        }

        fn _ValidateIndexType(index_t: type) void {
            const type_info = @typeInfo(index_t);

            if (type_info != .int and type_info != .comptime_int) {
                @compileError("index must be int type");
            }
        }
    };
}

fn AllSkipFn(comptime size: usize, comptime field_type: type) [size]field_type {
    @setEvalBranchQuota(5000);
    var arr: [size]field_type = std.mem.zeroes([size]field_type);
    for (0..size) |i| {
        arr[i] = 1;
    }
    arr[0] = size;
    arr[size - 1] = size;
    return arr;
}

test "Init Small Field" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == FieldSize);

    field = .NoSkip;
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To UnSkip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == 1);

    field.ChangeToUnskipped(0);
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To Skip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .NoSkip;
    try std.testing.expect(field.mSkipField[0] == 0);

    field.ChangeToSkipped(0);
    try std.testing.expect(field.mSkipField[0] == 1);
}

test "Init Large Field" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == FieldSize);
    try std.testing.expect(field.mSkipField[FieldSize - 1] == FieldSize);
    for (1..FieldSize - 2) |i| {
        try std.testing.expect(field.mSkipField[i] == 1);
    }

    field = .NoSkip;
    for (0..FieldSize) |i| {
        try std.testing.expect(field.mSkipField[i] == 0);
    }
}

test "Large Change To Skip" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .NoSkip;

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

    var field: SkipFieldT = .AllSkip;

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

    var field: SkipFieldT = .AllSkip;

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(0);

    var iter = field.Iterator();
    while (iter.next()) |i| {
        try std.testing.expect(i == 1 or i == 2 or i == 3);
    }
}

test "Iterating Skipfield 2" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(3);

    var iter = field.Iterator();
    while (iter.next()) |i| {
        try std.testing.expect(i == 0 or i == 1 or i == 2);
    }
}

test "Iterating Skipfield 3" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    field.ChangeToSkipped(4);
    field.ChangeToSkipped(2);
    field.ChangeToSkipped(3);

    var iter = field.Iterator();
    while (iter.next()) |i| {
        try std.testing.expect(i == 0 or i == 1);
    }
}

test "Test Zeros Mask" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    try std.testing.expect(field.HasSameUnskipped(&mask));

    mask.ChangeToUnskipped(3);

    try std.testing.expect(!field.HasSameUnskipped(&mask));

    field.ChangeToUnskipped(3);

    try std.testing.expect(field.HasSameUnskipped(&mask));
}

test "Test Union" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    field.Union(&mask);

    try std.testing.expect(field.IndexIsUnskipped(1));

    mask.ChangeToSkipped(1);

    field.Union(&mask);

    try std.testing.expect(!field.IndexIsUnskipped(1));
}

test "Test Intersection" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(2);

    field.Intersect(&mask);

    try std.testing.expect(field.IndexIsUnskipped(1));
    try std.testing.expect(field.IndexIsUnskipped(2));

    field.ChangeToUnskipped(3);

    field.Intersect(&mask);

    try std.testing.expect(field.IndexIsUnskipped(3));
}

test "Test Difference" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    field.Difference(&mask);

    try std.testing.expect(!field.IndexIsUnskipped(1));
}

test "Matches Mask" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT.SkipFieldArrayT = SkipFieldT.SkipFieldArrayT{ 1, 1, 1, 1, 1 };
    var mask_vec: SkipFieldT.SkipFieldVectorT = undefined;

    field.ChangeToUnskipped(1);
    mask[1] = 0;
    mask_vec = mask;

    try std.testing.expect(field.MatchesMask(&mask_vec));

    mask[2] = 0;
    mask_vec = mask;

    try std.testing.expect(!field.MatchesMask(&mask_vec));

    field.ChangeToUnskipped(2);

    try std.testing.expect(field.MatchesMask(&mask_vec));
}

test "IsAllUnskipped" {
    const FieldSize = 3;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    try std.testing.expect(field.IsAllUnskipped() == false);

    field.ChangeToUnskipped(0);
    field.ChangeToUnskipped(1);
    field.ChangeToUnskipped(2);

    try std.testing.expect(field.IsAllUnskipped() == true);

    field.ChangeToSkipped(1);

    try std.testing.expect(field.IsAllUnskipped() == false);
}

test "GetFirstUnskipped" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(3);

    try std.testing.expect(field.GetFirstUnskipped() == 3);

    field.ChangeToUnskipped(4);

    try std.testing.expect(field.GetFirstUnskipped() == 3);

    field.ChangeToUnskipped(1);

    try std.testing.expect(field.GetFirstUnskipped() == 1);
}
