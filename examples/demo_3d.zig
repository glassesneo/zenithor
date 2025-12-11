const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const ResourceMut = zenithor.ResourceMut;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, Game }, .{});
}

// Demo state for animation
const DemoState = struct {
    time: f32 = 0,
};

fn setup(commands: anytype) !void {
    // Create a box
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 1.0, .height = 1.0, .depth = 1.0 },
        Transform{ .x = -2.0, .y = 0, .z = 0 },
        Color.red,
    });

    // Create a sphere
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 24, .stacks = 18 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Color.green,
    });

    // Create a cylinder
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.4, .height = 1.2, .slices = 20 },
        Transform{ .x = 2.0, .y = 0, .z = 0 },
        Color.blue,
    });

    // Create a torus
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Torus3D{ .radius = 0.5, .ring_radius = 0.15, .sides = 24, .rings = 24 },
        Transform{ .x = 0, .y = 2.0, .z = 0 },
        Color.yellow,
    });

    // Create a ground plane
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Plane3D{ .width = 10.0, .depth = 10.0, .tiles = 10 },
        Transform{ .x = 0, .y = -1.5, .z = 0 },
        Color{ .r = 0.4, .g = 0.4, .b = 0.4, .a = 1.0 },
    });

    // Initialize demo state
    commands.setResource(DemoState, .{});
}

fn animateCamera(
    camera: ResourceMut(GraphicsPlugin.Camera3D),
    demo: ResourceMut(DemoState),
) void {
    // Update time
    demo.value.time += 0.016; // Approximate frame time

    // Orbit camera around the scene
    const radius: f32 = 8.0;
    const angle = demo.value.time * 0.3;
    camera.value.eye = .{
        radius * @cos(angle),
        3.0,
        radius * @sin(angle),
    };
    camera.value.target = .{ 0, 0, 0 };
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};
    pub const Resources = .{DemoState};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = animateCamera, .stage = .pre_update },
        },
    };
};
