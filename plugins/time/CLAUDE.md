# Time Plugin

Frame timing and FPS tracking.

## Resources

**Time** (non-serializable)
- `delta_time: f32` - Frame delta in seconds (clamped to 100ms max)
- `total_time: f64` - Elapsed time since start
- `frame_count: u64` - Total frames rendered
- `fps: f32` - Smoothed FPS (exponential moving average)
- `time_scale: f32` - Global speed multiplier (1.0 = normal, 0.0 = paused)
- `fps_smoothing_factor: f32` - EMA alpha (default 0.1)

## Usage

```zig
const Time = @import("time").Time;

fn movement(time: Resource(Time), entities: Query(struct { Position, Velocity })) !void {
    const dt = time.value.delta_time * time.value.time_scale;
    for (entities.entities) |entity| {
        const pos = entities.getComponentMut(entity, Position);
        const vel = entities.getComponent(entity, Velocity);
        pos.x += vel.x * dt;
        pos.y += vel.y * dt;
    }
}
```

## Implementation Notes

- Updates run in `.first` stage (before user systems)
- Delta time clamped to prevent physics explosions on lag/deserialization
- Uses `sokol.time` for high-precision timing (initialized in core/application.zig)
- `time_scale` affects only scaled delta calculations (user must apply manually)
