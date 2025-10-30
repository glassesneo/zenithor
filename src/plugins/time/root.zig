const std = @import("std");
const sokol = @import("sokol");
const sparze = @import("sparze");

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

/// Time resource containing all time-related state
pub const Time = struct {
    /// Frame delta time in seconds (unscaled)
    delta_time: f32 = 0.0,

    /// Total elapsed time since application start in seconds
    total_time: f64 = 0.0,

    /// Total number of frames rendered
    frame_count: u64 = 0,

    /// Current frames per second (smoothed using exponential moving average)
    fps: f32 = 0.0,

    /// Global time scaling factor (1.0 = normal speed, 0.0 = pause, 0.5 = half speed)
    time_scale: f32 = 1.0,

    /// Private: Last frame ticks for delta calculation
    last_frame_ticks: u64 = 0,

    /// FPS smoothing factor (lower = smoother, higher = more responsive)
    fps_smoothing_factor: f32 = 0.1,
};

pub const Components = .{};
pub const Resources = .{
    Time,
};

pub const Events = .{};

fn init() !void {
    sokol.time.setup();
}

fn update(time: sparze.Resource(Time)) !void {
    // Measure frame time using sokol_time's laptime
    const frame_ticks = sokol.time.laptime(&time.value.last_frame_ticks);
    const raw_delta_time = sokol.time.sec(frame_ticks);

    // Update time state
    time.value.delta_time = @floatCast(raw_delta_time);
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

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Initialize Time resource with default values
    try world.setResource(Time, .{});

    registry.registerStartupSystem(init, .first);
    registry.registerSystem(update, .first);
}
