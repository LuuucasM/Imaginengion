//! Sparse Set
//!
//! Version 1.0.2
//!
//! See https://github.com/Srekel/zig-sparse-set for latest version and documentation.
//!
//! See unit tests for usage examples.
//!
//! Dual license: Unlicense / MIT
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const AllowResize = union(enum) {
    /// The fields **dense_to_sparse** and **values** will grow on **add()** and **addValue()**.
    ResizeAllowed,

    /// Errors will be generated when adding more elements than **capacity_dense**.
    NoResize,
};

pub const ValueLayout = union(enum) {
    /// AOS style.
    InternalArrayOfStructs,

    /// SOA style.
    ExternalStructOfArraysSupport,
};

pub const ValueInitialization = union(enum) {
    /// New values added with add() will contain uninitialized/random memory.
    Untouched,

    /// New values added with add() will be memset to zero.
    ZeroInitialized,
};

pub const SparseSetConfig = struct {
    /// The type used for the sparse handle.
    SparseT: type,

    /// The type used for dense indices.
    DenseT: type,

    /// Optional: The type used for values when using **InternalArrayOfStructs**.
    ValueT: type = void,

    /// If you only have a single array of structs - AOS - letting SparseSet handle it
    /// with **InternalArrayOfStructs** is convenient. If you want to manage the data
    /// yourself or if you're using SOA, use **ExternalStructOfArraysSupport**.
    value_layout: ValueLayout,

    /// Set to **ZeroInitialized** to make values created with add() be zero initialized.
    /// Only valid with **value_layout == .InternalArrayOfStructs**.
    /// Defaults to **Untouched**.
    value_init: ValueInitialization = .Untouched,

    /// Whether or not the amount of dense indices (and values) can grow.
    allow_resize: AllowResize = .NoResize,
};

/// Creates a specific Sparse Set type based on the config.
pub fn SparseSet(comptime config: SparseSetConfig) type {
    const SparseT = config.SparseT;
    const DenseT = config.DenseT;
    const ValueT = config.ValueT;
    const allow_resize = config.allow_resize;
    const value_layout = config.value_layout;
    const value_init = config.value_init;
    assert((value_layout == .ExternalStructOfArraysSupport) or (ValueT != @TypeOf(void)));

    return struct {
        const Self = @This();
        pub const SparseCapacityT = std.math.IntFittingRange(0, std.math.maxInt(SparseT) + 1);
        pub const DenseCapacityT = std.math.IntFittingRange(0, std.math.maxInt(DenseT) + 1);

        /// Allocator used for allocating, growing and freeing **dense_to_sparse**, **sparse_to_dense**, and **values**.
        allocator: Allocator,

        /// Mapping from dense indices to sparse handles.
        dense_to_sparse: []SparseT,

        /// Mapping from sparse handles to dense indices (and values).
        sparse_to_dense: []DenseT,

        /// Optional: A list of **ValueT** that is used with **InternalArrayOfStructs**.
        values: if (value_layout == .InternalArrayOfStructs) []ValueT else void,

        /// Current amount of used handles.
        dense_count: DenseCapacityT,

        /// Amount of dense indices that can be stored.
        capacity_dense: DenseCapacityT,

        /// Amount of sparse handles that can be used for lookups.
        capacity_sparse: SparseCapacityT,

        /// You can think of **capacity_sparse** as how many entities you want to support, and
        /// **capacity_dense** as how many components.
        pub fn init(
            allocator: Allocator,
            capacity_sparse: SparseCapacityT,
            capacity_dense: DenseCapacityT,
        ) !Self {
            assert(capacity_dense <= capacity_sparse);

            const dense_to_sparse = try allocator.alloc(SparseT, @intCast(capacity_dense));
            errdefer allocator.free(dense_to_sparse);
            const sparse_to_dense = try allocator.alloc(DenseT, @intCast(capacity_sparse));
            errdefer allocator.free(sparse_to_dense);

            var self: Self = undefined;
            if (value_layout == .InternalArrayOfStructs) {
                const values = try allocator.alloc(ValueT, @intCast(capacity_dense));
                errdefer allocator.free(values);

                self = Self{
                    .allocator = allocator,
                    .dense_to_sparse = dense_to_sparse,
                    .sparse_to_dense = sparse_to_dense,
                    .values = values,
                    .capacity_dense = capacity_dense,
                    .capacity_sparse = capacity_sparse,
                    .dense_count = 0,
                };
            } else {
                self = Self{
                    .allocator = allocator,
                    .dense_to_sparse = dense_to_sparse,
                    .sparse_to_dense = sparse_to_dense,
                    .values = {},
                    .capacity_dense = capacity_dense,
                    .capacity_sparse = capacity_sparse,
                    .dense_count = 0,
                };
            }

            // Ensure Valgrind doesn't complain about hasSparse
            _ = std.valgrind.memcheck.makeMemDefined(std.mem.asBytes(&self.sparse_to_dense));

            return self;
        }

        /// Deallocates **dense_to_sparse**, **sparse_to_dense**, and optionally **values**.
        pub fn deinit(self: Self) void {
            self.allocator.free(self.dense_to_sparse);
            self.allocator.free(self.sparse_to_dense);
            if (value_layout == .InternalArrayOfStructs) {
                self.allocator.free(self.values);
            }
        }

        /// Resets the set cheaply.
        pub fn clear(self: *Self) void {
            self.dense_count = 0;
        }

        /// Returns the amount of allocated handles.
        pub fn len(self: Self) DenseCapacityT {
            return self.dense_count;
        }

        /// Returns a slice that can be used to loop over the sparse handles.
        pub fn toSparseSlice(self: Self) []SparseT {
            return self.dense_to_sparse[0..self.dense_count];
        }

        // A bit of a hack to comptime add a function
        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                /// Returns a slice that can be used to loop over the values.
                pub fn toValueSlice(self: Self) []ValueT {
                    return self.values[0..self.dense_count];
                }
            },
            else => struct {},
        };

        /// Returns how many dense indices are still available
        pub fn remainingCapacity(self: Self) DenseCapacityT {
            return self.capacity_dense - self.dense_count;
        }

        /// Registers the sparse value and matches it to a dense index.
        /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
        /// Note: If resizing is allowed, you must use an allocator that you are sure
        /// will never fail for your use cases.
        /// If that is not an option, use addOrError.
        pub fn add(self: *Self, sparse: SparseT) DenseT {
            if (allow_resize == .ResizeAllowed) {
                if (self.dense_count == self.capacity_dense) {
                    self.capacity_dense = self.capacity_dense * 2;
                    self.dense_to_sparse = self.allocator.realloc(self.dense_to_sparse, @intCast(self.capacity_dense)) catch unreachable;
                    if (value_layout == .InternalArrayOfStructs) {
                        self.values = self.allocator.realloc(self.values, @intCast(self.capacity_dense)) catch unreachable;
                    }
                }
                while (sparse >= self.sparse_to_dense.len) {
                    self.capacity_sparse = self.capacity_sparse * 2;
                    self.sparse_to_dense = self.allocator.realloc(self.sparse_to_dense, @intCast(self.capacity_sparse)) catch unreachable;
                }
            }

            assert(sparse < self.capacity_sparse);
            assert(self.dense_count < self.capacity_dense);
            assert(!self.hasSparse(sparse));
            self.dense_to_sparse[@intCast(self.dense_count)] = sparse;
            self.sparse_to_dense[sparse] = @intCast(self.dense_count);
            if (value_layout == .InternalArrayOfStructs and value_init == .ZeroInitialized) {
                self.values[self.dense_count] = std.mem.zeroes(ValueT);
            }

            self.dense_count += 1;
            return @intCast(self.dense_count - 1);
        }

        /// May return error.OutOfBounds or error.AlreadyRegistered, otherwise calls add.
        /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
        pub fn addOrError(self: *Self, sparse: SparseT) !DenseT {
            if (sparse >= self.capacity_sparse) {
                return error.OutOfBounds;
            }

            if (try self.hasSparseOrError(sparse)) {
                return error.AlreadyRegistered;
            }

            if (self.dense_count == self.capacity_dense) {
                if (allow_resize == .ResizeAllowed) {
                    self.capacity_dense = self.capacity_dense * 2;
                    self.dense_to_sparse = try self.allocator.realloc(self.dense_to_sparse, self.capacity_dense);
                    if (value_layout == .InternalArrayOfStructs) {
                        self.values = try self.allocator.realloc(self.values, self.capacity_dense);
                    }
                    while (sparse >= self.sparse_to_dense.len) {
                        const new_cap = self.sparse_to_dense.len * 2;
                        self.sparse_to_dense = self.allocator.realloc(self.sparse_to_dense, @intCast(new_cap)) catch unreachable;
                    }
                } else {
                    return error.OutOfBounds;
                }
            }

            return self.add(sparse);
        }

        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                /// Registers the sparse value and matches it to a dense index
                /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
                /// Note: If resizing is allowed, you must use an allocator that you are sure
                /// will never fail for your use cases.
                ///  If that is not an option, use addOrError.
                pub fn addValue(self: *Self, sparse: SparseT, value: ValueT) DenseT {
                    if (allow_resize == .ResizeAllowed) {
                        if (self.dense_count == self.capacity_dense) {
                            self.capacity_dense = self.capacity_dense * 2;
                            self.dense_to_sparse = self.allocator.realloc(self.dense_to_sparse, self.capacity_dense) catch unreachable;
                            if (value_layout == .InternalArrayOfStructs) {
                                self.values = self.allocator.realloc(self.values, self.capacity_dense) catch unreachable;
                            }
                        }
                        while (sparse >= self.sparse_to_dense.len) {
                            self.capacity_sparse = self.capacity_sparse * 2;
                            self.sparse_to_dense = self.allocator.realloc(self.sparse_to_dense, @intCast(self.capacity_sparse)) catch unreachable;
                        }
                    }

                    assert(sparse < self.capacity_sparse);
                    assert(self.dense_count < self.capacity_dense);
                    assert(!self.hasSparse(@intCast(sparse)));
                    self.dense_to_sparse[self.dense_count] = sparse;
                    self.sparse_to_dense[@intCast(sparse)] = @intCast(self.dense_count);
                    self.values[self.dense_count] = value;
                    self.dense_count += 1;
                    return @intCast(self.dense_count - 1);
                }

                /// May return error.OutOfBounds or error.AlreadyRegistered, otherwise calls add.
                /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
                pub fn addValueOrError(self: *Self, sparse: SparseT, value: ValueT) !DenseT {
                    if (sparse >= self.capacity_sparse) {
                        return error.OutOfBounds;
                    }

                    if (try self.hasSparseOrError(sparse)) {
                        return error.AlreadyRegistered;
                    }

                    if (self.dense_count == self.capacity_dense) {
                        if (allow_resize == .ResizeAllowed) {
                            self.capacity_dense = self.capacity_dense * 2;
                            self.dense_to_sparse = try self.allocator.realloc(self.dense_to_sparse, self.capacity_dense);
                            if (value_layout == .InternalArrayOfStructs) {
                                self.values = try self.allocator.realloc(self.values, self.capacity_dense);
                            }
                        } else {
                            return error.OutOfBounds;
                        }
                    }

                    return self.addValue(sparse, value);
                }
            },
            else => struct {},
        };

        /// Removes the sparse/dense index, and replaces it with the last ones.
        /// dense_old and dense_new is
        pub fn removeWithInfo(self: *Self, sparse: SparseT, dense_old: *DenseT, dense_new: *DenseT) void {
            assert(self.dense_count > 0);
            assert(self.hasSparse(sparse));
            const last_dense: DenseT = @intCast(self.dense_count - 1);
            const last_sparse = self.dense_to_sparse[last_dense];
            const dense = self.sparse_to_dense[sparse];
            self.dense_to_sparse[dense] = last_sparse;
            self.sparse_to_dense[last_sparse] = dense;
            if (value_layout == .InternalArrayOfStructs) {
                self.values[dense] = self.values[last_dense];
            }

            self.dense_count -= 1;
            dense_old.* = last_dense;
            dense_new.* = dense;
        }

        /// May return error.OutOfBounds, otherwise calls removeWithInfo.
        pub fn removeWithInfoOrError(self: *Self, sparse: SparseT, dense_old: *DenseT, dense_new: *DenseT) !void {
            if (self.dense_count == 0) {
                return error.OutOfBounds;
            }

            if (!try self.hasSparseOrError(sparse)) {
                return error.NotRegistered;
            }

            return self.removeWithInfo(sparse, dense_old, dense_new);
        }

        /// Like removeWithInfo info, but slightly faster, in case you don't care about the switch.
        pub fn remove(self: *Self, sparse: SparseT) void {
            assert(self.dense_count > 0);
            assert(self.hasSparse(sparse));
            const last_dense = self.dense_count - 1;
            const last_sparse = self.dense_to_sparse[@intCast(last_dense)];
            const dense = self.sparse_to_dense[sparse];
            self.dense_to_sparse[dense] = last_sparse;
            self.sparse_to_dense[last_sparse] = dense;
            if (value_layout == .InternalArrayOfStructs) {
                self.values[dense] = self.values[@intCast(last_dense)];
            }

            self.dense_count -= 1;
        }

        /// May return error.OutOfBounds or error.NotRegistered, otherwise calls remove.
        pub fn removeOrError(self: *Self, sparse: SparseT) !void {
            if (self.dense_count == 0) {
                return error.OutOfBounds;
            }

            if (!try self.hasSparseOrError(sparse)) {
                return error.NotRegistered;
            }

            self.remove(sparse);
        }

        pub fn orderedRemove(self: *Self, sparse: SparseT) void {
            const start = self.getBySparse(sparse);
            const after_range = start + 1;
            //remove value
            std.mem.copyForwards(ValueT, self.values[after_range - 1 ..], self.values[after_range..]);
            //remove dense
            std.mem.copyForwards(SparseT, self.dense_to_sparse[after_range - 1 ..], self.dense_to_sparse[after_range..]);
            //starting from dense at i (sparselist[sprase]) decrease sprase value by 1
            for (self.dense_to_sparse[start .. self.dense_count - 1]) |sparse_id| {
                self.sparse_to_dense[@intCast(sparse_id)] -= 1;
            }
            self.dense_count -= 1;
        }

        pub fn move(self: *Self, sparse: SparseT, new_pos: usize) void {
            const current_pos = self.getBySparse(sparse);
            if (new_pos == current_pos) return;

            const value = self.getValueBySparse(sparse).*;

            if (new_pos < current_pos) {
                std.mem.copyBackwards(ValueT, self.values[new_pos + 1 .. current_pos + 1], self.values[new_pos..current_pos]);
                std.mem.copyBackwards(SparseT, self.dense_to_sparse[new_pos + 1 .. current_pos + 1], self.dense_to_sparse[new_pos..current_pos]);

                for (self.dense_to_sparse[new_pos + 1 .. current_pos + 1]) |sparse_id| {
                    self.sparse_to_dense[@intCast(sparse_id)] += 1;
                }
            } else {
                std.mem.copyForwards(ValueT, self.values[current_pos..new_pos], self.values[current_pos + 1 .. new_pos + 1]);
                std.mem.copyForwards(SparseT, self.dense_to_sparse[current_pos..new_pos], self.dense_to_sparse[current_pos + 1 .. new_pos + 1]);

                for (self.dense_to_sparse[current_pos..new_pos]) |sparse_id| {
                    self.sparse_to_dense[@intCast(sparse_id)] -= 1;
                }
            }
            self.values[new_pos] = value;
            self.dense_to_sparse[new_pos] = sparse;
            self.sparse_to_dense[sparse] = @intCast(new_pos);
        }

        /// Returns true if the sparse is registered to a dense index.
        pub fn hasSparse(self: Self, sparse: SparseT) bool {
            // Unsure if this call to disable runtime safety is needed - can add later if so.
            // Related: https://github.com/ziglang/zig/issues/978
            // @setRuntimeSafety(false);
            assert(sparse < self.capacity_sparse);
            const dense = self.sparse_to_dense[@intCast(sparse)];
            return dense < self.dense_count and self.dense_to_sparse[dense] == sparse;
        }

        /// May return error.OutOfBounds, otherwise calls hasSparse.
        pub fn hasSparseOrError(self: Self, sparse: SparseT) !bool {
            if (sparse >= self.capacity_sparse) {
                return error.OutOfBounds;
            }

            return self.hasSparse(sparse);
        }

        ///Returns true if the sparse is registered to a dense index, but will not have an error if sprase is out of bounds
        pub fn HasSparse(self: Self, sparse: SparseT) bool {
            if (sparse >= self.capacity_sparse) return false;
            return self.hasSparse(sparse);
        }

        /// Returns corresponding dense index.
        pub fn getBySparse(self: Self, sparse: SparseT) DenseT {
            assert(self.hasSparse(@intCast(sparse)));
            return self.sparse_to_dense[@intCast(sparse)];
        }

        /// Tries hasSparseOrError, then returns getBySparse.
        pub fn getBySparseOrError(self: Self, sparse: SparseT) !DenseT {
            if (!try self.hasSparseOrError(sparse)) {
                return error.NotRegistered;
            }

            return self.getBySparse(sparse);
        }

        /// Returns corresponding sparse index.
        pub fn getByDense(self: Self, dense: DenseT) SparseT {
            assert(dense < self.dense_count);
            return self.dense_to_sparse[dense];
        }

        /// Returns OutOfBounds or getByDense.
        pub fn getByDenseOrError(self: Self, dense: DenseT) !SparseT {
            if (dense >= self.dense_count) {
                return error.OutOfBounds;
            }
            return self.getByDense(dense);
        }

        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                /// Returns a pointer to the SOA value corresponding to the sparse parameter.
                pub fn getValueBySparse(self: Self, sparse: SparseT) *ValueT {
                    assert(self.hasSparse(sparse));
                    const dense = self.sparse_to_dense[@intCast(sparse)];
                    return &self.values[dense];
                }

                /// First tries hasSparse, then returns getValueBySparse().
                pub fn getValueBySparseOrError(self: Self, sparse: SparseT) !*ValueT {
                    if (!try self.hasSparseOrError(sparse)) {
                        return error.NotRegistered;
                    }
                    return self.getValueBySparse(sparse);
                }

                /// Returns a pointer to the SOA value corresponding to the sparse parameter.
                pub fn getValueByDense(self: Self, dense: DenseT) *ValueT {
                    assert(dense < self.dense_count);
                    return &self.values[dense];
                }

                /// Returns error.OutOfBounds or getValueByDense().
                pub fn getValueByDenseOrError(self: Self, dense: DenseT) !*ValueT {
                    if (dense >= self.dense_count) {
                        return error.OutOfBounds;
                    }
                    return self.getValueByDense(dense);
                }
            },
            else => struct {},
        };
    };
}

test "docs" {
    const Entity = u32;
    const DenseT = u8;
    const DocValueT = i32;
    const DocsSparseSet = SparseSet(.{
        .SparseT = Entity,
        .DenseT = DenseT,
        .ValueT = DocValueT,
        .allow_resize = .NoResize,
        .value_layout = .InternalArrayOfStructs,
    });

    var ss = DocsSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    const ent1: Entity = 1;
    const ent2: Entity = 2;
    _ = try ss.addOrError(ent1);
    _ = try ss.addValueOrError(ent2, 2);
    try std.testing.expectEqual(@as(DocsSparseSet.DenseCapacityT, 2), ss.len());
    try ss.removeOrError(ent1);
    var old: DenseT = undefined;
    var new: DenseT = undefined;
    try ss.removeWithInfoOrError(ent2, &old, &new);
    _ = ss.toSparseSlice();
    _ = ss.toValueSlice();
    try std.testing.expectEqual(@as(DocsSparseSet.DenseCapacityT, 0), ss.len());
    ss.clear();
    try std.testing.expectEqual(@as(DocsSparseSet.DenseCapacityT, 8), ss.remainingCapacity());

    _ = try ss.addValueOrError(ent1, 10);
    try std.testing.expectEqual(@as(DenseT, 0), try ss.getBySparseOrError(ent1));
    try std.testing.expectEqual(@as(DocValueT, 10), (try ss.getValueBySparseOrError(ent1)).*);
    try std.testing.expectEqual(@as(Entity, ent1), try ss.getByDenseOrError(0));
    try std.testing.expectEqual(@as(DocValueT, 10), (try ss.getValueByDenseOrError(0)).*);
}

test "orderedRemove" {
    const Entity = u32;
    const DenseT = u8;
    const DocValueT = i32;
    const DocsSparseSet = SparseSet(.{
        .SparseT = Entity,
        .DenseT = DenseT,
        .ValueT = DocValueT,
        .allow_resize = .ResizeAllowed,
        .value_layout = .InternalArrayOfStructs,
    });

    var ss = DocsSparseSet.init(std.testing.allocator, 4, 4) catch unreachable;
    defer ss.deinit();
    const ent1: Entity = 1;
    const ent2: Entity = 2;
    const ent3: Entity = 3;
    const ent4: Entity = 4;
    const ent5: Entity = 5;

    _ = ss.addValue(ent1, 10);
    _ = ss.addValue(ent2, 20);
    _ = ss.addValue(ent3, 30);
    _ = ss.addValue(ent4, 40);
    _ = ss.addValue(ent5, 50);

    ss.orderedRemove(ent3);
    try std.testing.expect(ss.dense_count == 4);
    try std.testing.expect(ss.dense_to_sparse[2] == 4);
    try std.testing.expect(ss.values[2] == 40);

    ss.orderedRemove(ent5);
    try std.testing.expect(ss.dense_count == 3);
    try std.testing.expect(ss.dense_to_sparse[2] == 4);
    try std.testing.expect(ss.values[2] == 40);

    ss.orderedRemove(ent1);
    try std.testing.expect(ss.dense_count == 2);
    try std.testing.expect(ss.dense_to_sparse[1] == 4);
    try std.testing.expect(ss.values[1] == 40);
}

test "move" {
    const Entity = u32;
    const DenseT = u8;
    const DocValueT = i32;
    const DocsSparseSet = SparseSet(.{
        .SparseT = Entity,
        .DenseT = DenseT,
        .ValueT = DocValueT,
        .allow_resize = .ResizeAllowed,
        .value_layout = .InternalArrayOfStructs,
    });

    var ss = DocsSparseSet.init(std.testing.allocator, 4, 4) catch unreachable;
    defer ss.deinit();
    const ent1: Entity = 1;
    const ent2: Entity = 2;
    const ent3: Entity = 3;
    const ent4: Entity = 4;
    const ent5: Entity = 5;

    _ = ss.addValue(ent1, 10);
    _ = ss.addValue(ent2, 20);
    _ = ss.addValue(ent3, 30);
    _ = ss.addValue(ent4, 40);
    _ = ss.addValue(ent5, 50);

    ss.move(ent1, 4);
    try std.testing.expect(ss.sparse_to_dense[ent5] == 3);
    try std.testing.expect(ss.sparse_to_dense[ent1] == 4);

    ss.move(ent3, 1);
    try std.testing.expect(ss.sparse_to_dense[ent3] == 1);

    ss.move(ent4, 0);
    try std.testing.expect(ss.sparse_to_dense[ent4] == 0);
    try std.testing.expect(ss.sparse_to_dense[ent2] == 1);
}
