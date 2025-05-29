//! Provides a fixed-size circular buffer for generic types with optional reverse iteration.
//!
//! This module defines a generic `CircularBuffer(T, size)` type that stores elements in a
//! ring buffer layout. When the buffer reaches its capacity, new elements overwrite the oldest ones.
//!
//! The circular buffer supports:
//! - Pushing elements with automatic wrap-around.
//! - Peeking at the most recent or previous entries.
//! - Iterating backward over recent entries via a built-in `LookBackIterator`.
//!
//! Useful for scenarios like:
//! - Logging recent events or state changes.
//! - Implementing undo/redo stacks.
//! - Buffers in real-time systems where memory reuse is critical.
const std = @import("std");

pub fn CircularBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        _Buffer: [size]T = std.mem.zeroes([size]T),
        _Head: usize = 0,
        _Count: usize = 0,

        /// An iterator that walks backward through the buffer contents,
        /// starting from the most recently added entry.
        pub const LookBackIterator = struct {
            _BufferPtr: *[size]T,
            _Current: usize,
            _remaining: usize,

            /// Returns the next element when walking backward in the buffer.
            ///
            /// Returns:
            /// - `?T`: The next element in reverse order, or `null` when finished.
            pub fn Next(self: LookBackIterator) ?T {
                if (self._remaining == 0) return;
                const value = self._BufferPtr.*[self._Current];
                self._Current = if (self._Current == 0) size - 1 else self._Current - 1;
                return value;
            }
        };

        /// Returns the most recently pushed element in the buffer.
        ///
        /// Returns:
        /// - `T`: The element at the head of the buffer.
        ///
        /// Note: If the buffer is empty, this returns an uninitialized or overwritten element.
        pub fn Peak(self: Self) T {
            return self._Buffer[self._Head];
        }

        /// Inserts a new element into the buffer, overwriting the oldest entry if full.
        ///
        /// Parameters:
        /// - `entry`: The new element to add to the buffer.
        ///
        /// Automatically updates the head position and count.
        pub fn Push(self: Self, entry: T) void {
            self._Buffer[self._Head] = entry;
            self._Head = (self._Head + 1) % size;
            self._Count += 1;
        }

        /// Returns the most recent value before the current head.
        ///
        /// Returns:
        /// - `?T`: The most recently pushed element (excluding the current head slot).
        ///
        /// Useful for quick access to the last pushed value.
        pub fn Lookback(self: Self) ?T {
            const ind = (self._Head + size - 1) % size;
            return self._Buffer[ind];
        }

        /// Returns an iterator that walks backward through the buffer contents.
        ///
        /// Returns:
        /// - `LookBackIterator`: An iterator positioned at the last pushed element.
        ///
        /// The iterator stops after visiting all valid entries, up to `size`.
        pub fn LookbackIter(self: Self) LookBackIterator {
            return LookBackIterator{
                ._BufferPtr = &self._Buffer,
                ._Current = self._Head,
                ._remaining = if (self._Count < size) self._Count else size,
            };
        }
    };
}
