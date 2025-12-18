# Time Plugin

Frame timing, delta time, and FPS tracking.

## Resources

**Time** (non-serializable):
```zig
delta_time: f32          // Frame delta (seconds, clamped to 100ms)
total_time: f64          // Elapsed time since start
frame_count: u64         // Total frames rendered
fps: f32                 // Smoothed FPS (exponential moving average)
time_scale: f32          // Speed multiplier (1.0=normal, 0.0=paused)
fps_smoothing_factor: f32 // EMA alpha (default 0.1)
```

## Usage

```zig
const zenithor = @import("zenithor");
const Resource = zenithor.Resource;
const Query = zenithor.Query;
const Time = @import("time_plugin").Time;

fn movement(time: Resource(Time), entities: Query(struct { Position, Velocity })) !void {
    const dt = time.value.delta_time * time.value.time_scale;
    for (entities.entities) |entity| {
        const pos = entities.getComponentMut(entity, Position);
        const vel = entities.getComponent(entity, Velocity);
        pos.x += vel.x * dt;
    }
}
```

## Implementation

- Updates in `.first` stage (before user systems)
- Delta clamped to prevent physics explosions on lag/deserialization
- Uses sokol.time (initialized in core/application.zig)
- `time_scale` must be applied manually in systems

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
