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

/// Event capturing errors from event handlers (input, window events).
///
/// When an event handler returns an error, the application automatically catches it
/// and enqueues it as an EventLoopError event. This prevents event processing failures
/// from crashing the application.
///
/// Use `EventReader(EventLoopError)` to monitor event handler errors:
/// ```zig
/// fn eventErrorMonitor(errors: EventReader(EventLoopError)) !void {
///     for (errors.read()) |err_event| {
///         std.debug.print("Event handler error: {any}\n", .{err_event.err});
///     }
/// }
/// ```
///
/// This event is marked as non-serializable to prevent save/load systems
/// from persisting transient error states.
pub const EventLoopError = struct {
    pub const serialized = false;
    err: anyerror,
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

/// Builtin error events always included via BuiltinPlugin.
///
/// These events enable error recovery and monitoring:
/// - `GameLoopError` - System errors during frame execution
/// - `EventLoopError` - Event handler errors (input, window events)
///
/// Systems and event handlers can return `!void`. Errors are caught and enqueued as these events,
/// allowing the application to continue execution.
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md, docs/SYSTEM_ORDERING.md
pub const Events = .{
    GameLoopError,
    EventLoopError,
};

const std = @import("std");
