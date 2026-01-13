const sparze = @import("sparze");
const sokol = @import("sokol");

/// Position component in world space.
///
/// **Ubiquitous Language**: Transform, Position, World Space
///
/// Represents an entity's position in 3D space. Always included in every World via BuiltinPlugin.
///
/// **Coordinate system**:
/// - 2D graphics: Origin (0,0) at top-left, Y increases downward, Z = 0
/// - 3D graphics: Standard right-handed coordinates (Y up)
///
/// **Units**: Abstract units (interpret as pixels, meters, etc. based on your game)
///
/// **See Also**: @src/core/CLAUDE.md, docs/PLUGIN_DEVELOPMENT.md
pub const Transform = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn format(self: Transform, writer: anytype) !void {
        try writer.print("Transform(x: {d:.2}, y: {d:.2}, z: {d:.2})", .{ self.x, self.y, self.z });
    }
};

/// Rotation component for 3D objects (Euler angles in radians)
pub const Rotation = struct {
    x: f32 = 0, // Pitch (rotation around X axis)
    y: f32 = 0, // Yaw (rotation around Y axis)
    z: f32 = 0, // Roll (rotation around Z axis)

    pub fn format(self: Rotation, writer: anytype) !void {
        try writer.print("Rotation(x: {d:.2}, y: {d:.2}, z: {d:.2})", .{ self.x, self.y, self.z });
    }
};

/// Scale component for 3D objects
pub const Scale = struct {
    x: f32 = 1,
    y: f32 = 1,
    z: f32 = 1,

    /// Uniform scale (same value for all axes)
    pub fn uniform(s: f32) Scale {
        return .{ .x = s, .y = s, .z = s };
    }

    pub fn format(self: Scale, writer: anytype) !void {
        try writer.print("Scale(x: {d:.2}, y: {d:.2}, z: {d:.2})", .{ self.x, self.y, self.z });
    }
};

/// Color component with RGBA channels.
///
/// **Ubiquitous Language**: Color, Tint, Albedo, RGBA
///
/// Represents color with red, green, blue, and alpha channels. Always included in every World via BuiltinPlugin.
///
/// **Channel format**:
/// - Values in range [0.0, 1.0] (linear color space)
/// - `r`, `g`, `b`: Color channels
/// - `a`: Alpha (opacity), default 1.0 (fully opaque)
///
/// **Predefined colors**: `.red`, `.green`, `.blue`, `.yellow`, `.cyan`, `.magenta`, `.white`, `.black`, `.orange`, `.purple`
///
/// **See Also**: @src/core/CLAUDE.md, docs/PLUGIN_DEVELOPMENT.md
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    pub fn format(self: Color, writer: anytype) !void {
        try writer.print("Color(r: {d:.2}, g: {d:.2}, b: {d:.2}, a: {d:.2})", .{ self.r, self.g, self.b, self.a });
    }

    // Predefined colors for convenience
    pub const red = Color{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const green = Color{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const blue = Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const yellow = Color{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const cyan = Color{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const magenta = Color{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const white = Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const black = Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const orange = Color{ .r = 1.0, .g = 0.647, .b = 0.0, .a = 1.0 };
    pub const purple = Color{ .r = 0.502, .g = 0.0, .b = 0.502, .a = 1.0 };
};

/// Event capturing errors from systems during frame execution.
///
/// When a system returns an error, the SystemScheduler automatically catches it
/// and enqueues it as a GameLoopError event. This allows applications to continue
/// running despite system failures and implement custom error recovery logic.
///
/// Use `EventReader(GameLoopError)` to monitor system errors:
/// ```zig
/// fn errorMonitor(errors: EventReader(GameLoopError)) !void {
///     for (errors.read()) |err_event| {
///         std.debug.print("System error: {any}\n", .{err_event.err});
///     }
/// }
/// ```
///
/// This event is marked as non-serializable to prevent save/load systems
/// from persisting transient error states.
pub const GameLoopError = struct {
    pub const serialized = false;
    err: anyerror,
};

/// Sokol event queue resource for buffering events between frame boundaries.
///
/// **Ubiquitous Language**: Event Buffer, Double Buffer, Frame Snapshot
///
/// Events from Sokol callbacks are enqueued into a write buffer, then swapped
/// to become the read buffer at the start of each frame. Systems read from
/// the stable snapshot via `SokolEvents` parameter.
///
/// **Critical specifications**:
/// - Capacity: 1024 events per buffer
/// - Overflow policy: Drop events when write buffer is full
/// - `enqueue()`: Called from Sokol callback (no allocations, zero-copy)
/// - `drainToFrame()`: Swaps buffers (zero-copy operation)
/// - `read()`: Returns const slice of events for this frame
///
/// **Performance optimizations**:
/// - Double-buffering: Zero-copy buffer swap (eliminates N event copies per frame)
/// - Heap-allocated buffers: Avoids stack overflow on WASM (large inline arrays cause stack temps)
/// - Linear write buffer: Simple append-only during event capture, then swap and reset
///
/// **Latency**: 1 frame delay from Sokol callback to system processing
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md
pub const SokolEventQueue = struct {
    pub const capacity: usize = 1024;

    // Heap-allocated double-buffer slices (avoids WASM stack overflow)
    buffer0: []sokol.app.Event,
    buffer1: []sokol.app.Event,
    write_idx: u1 = 0, // Which buffer is currently being written to (0 or 1)

    write_head: usize = 0, // Write position in current write buffer
    read_count: usize = 0, // Number of events in the read buffer
    dropped_total: u64 = 0,

    /// Initialize the event queue with heap-allocated buffers.
    /// Sparze calls this automatically during World.init().
    pub fn init(allocator: std.mem.Allocator) @This() {
        const buffer0 = allocator.alloc(sokol.app.Event, capacity) catch @panic("Failed to allocate SokolEventQueue buffer0");
        const buffer1 = allocator.alloc(sokol.app.Event, capacity) catch @panic("Failed to allocate SokolEventQueue buffer1");

        return .{
            .buffer0 = buffer0,
            .buffer1 = buffer1,
        };
    }

    /// Clean up heap-allocated buffers.
    /// Sparze calls this automatically during World.deinit().
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.buffer0);
        allocator.free(self.buffer1);
    }

    fn getWriteBuffer(self: *@This()) []sokol.app.Event {
        return if (self.write_idx == 0) self.buffer0 else self.buffer1;
    }

    fn getReadBuffer(self: *const @This()) []sokol.app.Event {
        const read_idx = self.write_idx ^ 1;
        return if (read_idx == 0) self.buffer0 else self.buffer1;
    }

    /// Enqueues an event from Sokol callback.
    /// Drops event if write buffer is full.
    pub fn enqueue(self: *@This(), ev: sokol.app.Event) void {
        if (self.write_head >= capacity) {
            // Write buffer full - drop event
            self.dropped_total += 1;
            return;
        }
        self.getWriteBuffer()[self.write_head] = ev;
        self.write_head += 1;
    }

    /// Swaps write/read buffers (zero-copy operation).
    /// Called once per frame before systems run.
    pub fn drainToFrame(self: *@This()) void {
        // Swap buffers: flip write_idx (0→1, 1→0)
        self.write_idx ^= 1;

        // The OLD write buffer is now the read buffer
        self.read_count = self.write_head;

        // Reset write position for the NEW write buffer
        self.write_head = 0;
    }

    /// Returns events for this frame.
    /// Systems iterate this slice to process events.
    pub fn read(self: *const @This()) []const sokol.app.Event {
        return self.getReadBuffer()[0..self.read_count];
    }

    pub const serialized = false; // Don't persist event queue
};

/// Builtin components always included via BuiltinPlugin.
///
/// These components are automatically available in every World:
/// - `Transform` - Position in world space
/// - `Rotation` - Euler angles for 3D rotation
/// - `Scale` - Size scaling for 3D objects
/// - `Color` - RGBA color/tint
///
/// **Stability**: Always present, safe to assume in any plugin.
///
/// **See Also**: @src/core/CLAUDE.md
pub const Components = .{
    Transform,
    Rotation,
    Scale,
    Color,
};

/// Builtin resources always included via BuiltinPlugin.
///
/// These resources provide core functionality:
/// - `SokolEventQueue` - Buffered Sokol events for system processing
///
/// **See Also**: @src/core/CLAUDE.md
pub const Resources = .{
    SokolEventQueue,
};

/// Builtin error events always included via BuiltinPlugin.
///
/// These events enable error recovery and monitoring:
/// - `GameLoopError` - System errors during frame execution
///
/// Systems and event handlers can return `!void`. Errors are caught and enqueued as these events,
/// allowing the application to continue execution.
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md, docs/SYSTEM_ORDERING.md
pub const Events = .{
    GameLoopError,
};

const std = @import("std");
