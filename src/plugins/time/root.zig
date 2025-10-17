const std = @import("std");
const sokol = @import("sokol");

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

/// Frame delta time in seconds (scaled by time_scale)
pub var delta_time: f32 = 0.0;

/// Total elapsed time since application start in seconds
pub var total_time: f64 = 0.0;

/// Total number of frames rendered
pub var frame_count: u64 = 0;

/// Current frames per second (smoothed using exponential moving average)
pub var fps: f32 = 0.0;

/// Global time scaling factor (1.0 = normal speed, 0.0 = pause, 0.5 = half speed)
pub var time_scale: f32 = 1.0;

// Private state for time tracking
var last_frame_ticks: u64 = 0;
const fps_smoothing_factor: f32 = 0.1; // Lower = smoother, higher = more responsive

pub const Components = .{};

fn init() !void {
    sokol.time.setup();
    last_frame_ticks = 0;
}

fn update() !void {
    // Measure frame time using sokol_time's laptime
    const frame_ticks = sokol.time.laptime(&last_frame_ticks);
    const raw_delta_time = sokol.time.sec(frame_ticks);

    // Update global time state
    delta_time = @floatCast(raw_delta_time);
    total_time += raw_delta_time;
    frame_count += 1;

    // Calculate smoothed FPS using exponential moving average
    // Avoid division by zero on first frame or extremely fast frames
    if (delta_time > 0.0001) {
        const instant_fps = 1.0 / delta_time;
        // EMA: new_value = alpha * current + (1 - alpha) * previous
        fps = fps_smoothing_factor * instant_fps + (1.0 - fps_smoothing_factor) * fps;
    }
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerStartupSystem(init, .first);
    registry.registerSystem(update, .first);
}
