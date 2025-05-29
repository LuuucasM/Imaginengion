//! Provides a global engine context for runtime systems and dynamically loaded scripts.
//!
//! This module defines `EngineContext`, a globally accessible structure that exposes
//! shared runtime information such as input state and delta time. It is primarily intended
//! to serve dynamically loaded scripts (e.g., DLLs) that cannot access engine memory directly.
//!
//! The `EngineContext` acts as a bridge between the main engine and external modules,
//! enabling them to query frame-level data and engine-wide input state without direct
//! memory access to the host application.
//!
//! It currently supports:
//! - Access to the global `InputContext`.
//! - Access to the current frame's `delta time`.
//!
//! Usage:
//! - Call `Init()` during engine startup to set up internal pointers.
//! - Scripts can call `GetInstance()` to retrieve the global context pointer.
const StaticInputContext = @import("../Inputs/Input.zig");
const InputContext = @import("../Inputs/Input.zig").InputContext;

/// Singleton storage for the engine context.
var _StaticEngineContext: EngineContext = EngineContext{};

/// Represents shared runtime context accessible to external modules or scripts.
///
/// This struct is declared `extern` to ensure layout compatibility with foreign
/// (e.g., C or DLL) code. It contains pointers or values that represent runtime
/// state shared across engine boundaries.
pub const EngineContext = extern struct {
    /// Pointer to the input context used by the engine.
    ///
    /// Initialized during engine startup by `Init()`.
    _StaticInputContext: *InputContext = undefined,

    /// The frame delta time in seconds.
    ///
    /// Updated each frame using `SetDT()`.
    _DeltaTime: f32 = 0,

    /// Returns the current delta time (in seconds) for the frame.
    ///
    /// Useful for time-based calculations in scripts or systems.
    pub fn GetDeltaTime(self: *EngineContext) f32 {
        return self._DeltaTime;
    }

    /// Returns a pointer to the global input context.
    ///
    /// Allows access to input state (e.g., key presses, mouse state) from scripts.
    pub fn GetInputContext(self: *EngineContext) *InputContext {
        return self._StaticInputContext;
    }
};

/// Initializes the global engine context.
///
/// This must be called during engine startup to set the input context pointer.
/// If not called, any access to input state will result in undefined behavior.
pub fn Init() void {
    _StaticEngineContext._StaticInputContext = StaticInputContext.GetInstance();
}

/// Returns a pointer to the global engine context.
///
/// Intended for use by subsystems or dynamically loaded scripts that need
/// access to delta time or input state.
pub fn GetInstance() *EngineContext {
    return &_StaticEngineContext;
}

/// Updates the frame delta time in the global engine context.
///
/// This should be called once per frame with the elapsed time since the last frame.
///
/// Parameters:
/// - `delta_time`: Elapsed time (in seconds) since the previous frame.
pub fn SetDT(delta_time: f32) void {
    _StaticEngineContext._DeltaTime = delta_time;
}
