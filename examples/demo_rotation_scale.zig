const std = @import("std");
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Scale = zenithor.Scale;
const Color = zenithor.Color;
const ResourceMut = zenithor.ResourceMut;
const Resource = zenithor.Resource;
const Query = zenithor.Query;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;
const TimePlugin = @import("time_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, Game }, .{});
}

// Tag components to identify animated objects
const RotatingBox = struct {};
const ScalingBox = struct {};
const RotatingScalingSphere = struct {};
const OrbitingCylinder = struct {};

fn setup(commands: anytype) !void {
    // === Static shapes with various Rotation/Scale combinations ===

    // Box with rotation only (45 degrees around Y axis)
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.8, .height = 0.8, .depth = 0.8 },
        Transform{ .x = -4.0, .y = 0, .z = 0 },
        Rotation{ .x = 0, .y = std.math.pi / 4.0, .z = 0 },
        Color{ .r = 1.0, .g = 0.3, .b = 0.3, .a = 1.0 },
    });

    // Box with scale only (stretched along Y)
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.6, .height = 0.6, .depth = 0.6 },
        Transform{ .x = -2.0, .y = 0, .z = 0 },
        Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
        Color{ .r = 0.3, .g = 1.0, .b = 0.3, .a = 1.0 },
    });

    // Box with both rotation and scale (tilted and flattened)
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.8, .height = 0.8, .depth = 0.8 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Rotation{ .x = std.math.pi / 6.0, .y = std.math.pi / 4.0, .z = 0 },
        Scale{ .x = 1.5, .y = 0.5, .z = 1.0 },
        Color{ .r = 0.3, .g = 0.3, .b = 1.0, .a = 1.0 },
    });

    // === Animated shapes ===

    // Continuously rotating box
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.7, .height = 0.7, .depth = 0.7 },
        Transform{ .x = 2.0, .y = 0, .z = 0 },
        Rotation{ .x = 0, .y = 0, .z = 0 },
        Color{ .r = 1.0, .g = 0.6, .b = 0.0, .a = 1.0 },
        RotatingBox{},
    });

    // Pulsing scale box
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.6, .height = 0.6, .depth = 0.6 },
        Transform{ .x = 4.0, .y = 0, .z = 0 },
        Scale{ .x = 1.0, .y = 1.0, .z = 1.0 },
        Color{ .r = 0.8, .g = 0.0, .b = 0.8, .a = 1.0 },
        ScalingBox{},
    });

    // Sphere with both animated rotation and scale
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Sphere3D{ .radius = 0.5, .slices = 20, .stacks = 16 },
        Transform{ .x = 0, .y = 2.0, .z = 0 },
        Rotation{ .x = 0, .y = 0, .z = 0 },
        Scale{ .x = 1.0, .y = 1.0, .z = 1.0 },
        Color{ .r = 0.0, .g = 0.8, .b = 0.8, .a = 1.0 },
        RotatingScalingSphere{},
    });

    // Orbiting tilted cylinder
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.25, .height = 1.0, .slices = 16 },
        Transform{ .x = 0, .y = 0, .z = 3.0 },
        Rotation{ .x = std.math.pi / 4.0, .y = 0, .z = 0 },
        Scale{ .x = 1.0, .y = 1.5, .z = 1.0 },
        Color{ .r = 1.0, .g = 1.0, .b = 0.3, .a = 1.0 },
        OrbitingCylinder{},
    });

    // Ground plane
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Plane3D{ .width = 12.0, .depth = 12.0, .tiles = 12 },
        Transform{ .x = 0, .y = -1.5, .z = 0 },
        Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1.0 },
    });

    // Set up camera position
    commands.setResource(GraphicsPlugin.Camera3D, .{
        .eye = .{ 8.0, 5.0, 8.0 },
        .target = .{ 0, 0, 0 },
        .up = .{ 0, 1, 0 },
        .fov = 50.0,
        .near = 0.1,
        .far = 100.0,
    });

    // Set up lighting
    commands.setResource(GraphicsPlugin.Light3D, .{
        .position = .{ 5.0, 8.0, 5.0 },
        .color = .{ 1.0, 1.0, 1.0 },
        .ambient_strength = 0.15,
    });
}

fn animateRotatingBox(
    time: Resource(TimePlugin.Time),
    query: Query(struct { RotatingBox, Rotation }),
) void {
    const t = @as(f32, @floatCast(time.value.total_time));
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;
        const rot = query.getComponentMut(entity, Rotation);
        rot.x = t * 0.5;
        rot.y = t * 1.0;
        rot.z = t * 0.3;
    }
}

fn animateScalingBox(
    time: Resource(TimePlugin.Time),
    query: Query(struct { ScalingBox, Scale }),
) void {
    const t = @as(f32, @floatCast(time.value.total_time));
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;
        const scl = query.getComponentMut(entity, Scale);
        // Pulsing scale effect
        const pulse = 1.0 + 0.3 * @sin(t * 3.0);
        scl.x = pulse;
        scl.y = 1.0 + 0.5 * @sin(t * 2.0);
        scl.z = pulse;
    }
}

fn animateRotatingScalingSphere(
    time: Resource(TimePlugin.Time),
    query: Query(struct { RotatingScalingSphere, Rotation, Scale }),
) void {
    const t = @as(f32, @floatCast(time.value.total_time));
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;
        const rot = query.getComponentMut(entity, Rotation);
        const scl = query.getComponentMut(entity, Scale);

        // Tumbling rotation
        rot.x = t * 0.7;
        rot.y = t * 1.2;

        // Squash and stretch effect
        const phase = t * 2.5;
        scl.x = 1.0 + 0.2 * @sin(phase);
        scl.y = 1.0 - 0.2 * @sin(phase);
        scl.z = 1.0 + 0.2 * @sin(phase);
    }
}

fn animateOrbitingCylinder(
    time: Resource(TimePlugin.Time),
    query: Query(struct { OrbitingCylinder, Transform, Rotation }),
) void {
    const t = @as(f32, @floatCast(time.value.total_time));
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;
        const transform = query.getComponentMut(entity, Transform);
        const rot = query.getComponentMut(entity, Rotation);

        // Orbit around origin
        const orbit_radius: f32 = 3.0;
        const orbit_speed: f32 = 0.5;
        transform.x = orbit_radius * @cos(t * orbit_speed);
        transform.z = orbit_radius * @sin(t * orbit_speed);
        transform.y = 0.5 + 0.3 * @sin(t * 2.0);

        // Spin while orbiting
        rot.y = t * 2.0;
    }
}

const Game = struct {
    pub const Components = .{
        RotatingBox,
        ScalingBox,
        RotatingScalingSphere,
        OrbitingCylinder,
    };
    pub const Events = .{};
    pub const Resources = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = animateRotatingBox, .stage = .update },
            .{ .system = animateScalingBox, .stage = .update },
            .{ .system = animateRotatingScalingSphere, .stage = .update },
            .{ .system = animateOrbitingCylinder, .stage = .update },
        },
    };
};
