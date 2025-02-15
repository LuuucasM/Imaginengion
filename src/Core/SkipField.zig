const std = @import("std");

pub fn StaticSkipField(size: usize) type {
    return struct {
        const Self = @This();
        const InitOption = enum {
            AllSkip,
            NoSkip,
        };
        const SkipFieldType = std.math.IntFittingRange(0, size);

        mSkipField: [size]SkipFieldType = std.mem.zeroes([size]SkipFieldType),

        pub fn Init(option: InitOption) Self {
            var new_skipfield = Self{};
            if (option == .AllSkip) new_skipfield.Reset(option);
            return new_skipfield;
        }

        pub fn Reset(self: *Self, option: InitOption) void {
            if (option == .NoSkip) return;
            self.mSkipField[0] = size;
            self.mSkipField[size - 1] = size;
            var j: SkipFieldType = 1;
            while (j < size - 1) : (j += 1) {
                self.mSkipField[j] = j + 1;
            }
        }
        pub fn ChangeToSkipped(self: *Self, index: SkipFieldType) void {
            std.debug.assert(self.mSkipField.len > index);

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
        pub fn ChangeToUnskipped(self: *Self, index: SkipFieldType) void {
            std.debug.assert(self.mSkipField.len > index);

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
