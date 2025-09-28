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

        const SkipFieldType = std.math.IntFittingRange(0, size);

        mSkipField: [size]SkipFieldType = std.mem.zeroes([size]SkipFieldType),

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
                self.mSkipField[0] = size;
                self.mSkipField[size - 1] = size;
                var j: SkipFieldType = 1;
                while (j < size - 1) : (j += 1) {
                    self.mSkipField[j] = j + 1;
                }
            } else { //NoSkip option
                self.mSkipField = std.mem.zeroes([size]SkipFieldType);
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
                const left_value = self.mSkipField[index - 1];
                self.mSkipField[index] = 1 + left_value;
                self.mSkipField[index - left_value] = self.mSkipField[index];
            }
            //only right is non-zero
            else if (!left_non_zero and right_non_zero) {
                const right_value = self.mSkipField[index + 1];
                self.mSkipField[index] = right_value + 1;
                var i: SkipFieldType = 1;
                while (i <= right_value and index + i < size) : (i += 1) {
                    self.mSkipField[index + i] = i + 1;
                }
            }
            //both left and right are non-zero
            else {
                const left_value = self.mSkipField[index - 1];
                const right_value = self.mSkipField[index + 1];
                const new_value = left_value + right_value + 1;
                self.mSkipField[index - left_value] = new_value;
                var i: SkipFieldType = 0;
                while (i <= right_value and index + i < size) : (i += 1) {
                    self.mSkipField[index + i] = left_value + i + 1;
                }
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
                self.mSkipField[index] = 0;
            }
            //only left is non-zero
            else if (left_non_zero and !right_non_zero) {
                const current_value = self.mSkipField[index];
                self.mSkipField[index + 1 - current_value] = current_value - 1;
                self.mSkipField[index] = 0;
            }
            //only right is non-zero
            else if (!left_non_zero and right_non_zero) {
                const current_value = self.mSkipField[index];
                self.mSkipField[index] = 0;
                self.mSkipField[index + 1] = current_value - 1;

                var i: SkipFieldType = 2;
                while (i < current_value and index + i < size) : (i += 1) {
                    self.mSkipField[index + i] = i;
                }
            }
            //both left and right are non-zero
            else {
                const current_value = self.mSkipField[index];
                const left_start = index - (current_value - 1);
                const new_left_value = current_value - 1;
                const new_right_value = self.mSkipField[left_start] - current_value;

                self.mSkipField[left_start] = new_left_value;
                self.mSkipField[index] = 0;
                self.mSkipField[index + 1] = new_right_value;

                var i: SkipFieldType = 2;
                while (i <= new_right_value and index + i < size) : (i += 1) {
                    self.mSkipField[index + i] = i;
                }
            }
        }
    };
}
