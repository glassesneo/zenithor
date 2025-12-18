const std = @import("std");
const sokol = @import("sokol");
const sparze = @import("sparze");

const zenithor = @import("zenithor");
const Stage = zenithor.Stage;

/// Time resource containing all time-related state.
///
/// **Ubiquitous Language**: Time Resource, Delta Time, FPS, EMA (Exponential Moving Average)
///
/// Updated in `.first` stage (before most user systems). Provides frame timing for
/// physics, animation, and gameplay logic.
///
/// **Critical specifications**:
/// - `delta_time` is **clamped to 0.1s (100ms)** to prevent physics explosions on lag/deserialization
/// - `total_time` uses **raw delta** (no clamping applied)
/// - `time_scale` is **NOT automatically applied** - systems must multiply manually: `dt * time_scale`
/// - `fps` uses exponential moving average (EMA) with alpha = `fps_smoothing_factor` (default 0.1)
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md
pub const Time = struct {
    /// Frame delta time in seconds (clamped to 0.1s max)
    delta_time: f32 = 0.0,

    /// Total elapsed time since application start in seconds (uses raw delta, no clamp)
    total_time: f64 = 0.0,

    /// Total number of frames rendered
    frame_count: u64 = 0,

    /// Current frames per second (smoothed using exponential moving average)
    fps: f32 = 0.0,

    /// Global time scaling factor (1.0 = normal speed, 0.0 = pause, 0.5 = half speed)
    /// **IMPORTANT**: NOT automatically applied - multiply manually in systems
    time_scale: f32 = 1.0,

    /// Private: Last frame ticks for delta calculation
    last_frame_ticks: u64 = 0,

    /// FPS smoothing factor (lower = smoother, higher = more responsive)
    /// EMA formula: `fps = fps * (1 - alpha) + current_fps * alpha`
    fps_smoothing_factor: f32 = 0.1,

    /// Mark as non-serializable - time state should not be saved/loaded
    pub const serialized = false;
};

pub const Components = .{};
pub const Resources = .{
    Time,
};

pub const Events = .{};

// Note: sokol.time is initialized centrally in src/core/application.zig

fn update(time: sparze.ResourceMut(Time)) void {
    // Measure frame time using sokol_time's laptime
    const frame_ticks = sokol.time.laptime(&time.value.last_frame_ticks);
    const raw_delta_time = sokol.time.sec(frame_ticks);

    // Clamp delta time to prevent physics explosions on lag spikes or time jumps
    // This caps at 100ms (10 FPS minimum), preventing huge movements on deserialize or lag
    const MAX_DELTA = 0.1;
    const clamped_delta_time = @min(raw_delta_time, MAX_DELTA);

    // Update time state
    time.value.delta_time = @floatCast(clamped_delta_time);
    time.value.total_time += raw_delta_time;
    time.value.frame_count += 1;

    // Calculate smoothed FPS using exponential moving average
    // Avoid division by zero on first frame or extremely fast frames
    if (time.value.delta_time > 0.0001) {
        const instant_fps = 1.0 / time.value.delta_time;
        // EMA: new_value = alpha * current + (1 - alpha) * previous
        time.value.fps = time.value.fps_smoothing_factor * instant_fps + (1.0 - time.value.fps_smoothing_factor) * time.value.fps;
    }
}

fn init(commands: anytype) void {
    commands.setResource(Time, .{});
}

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = update, .stage = .first },
    },
};
