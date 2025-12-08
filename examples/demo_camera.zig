const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const GraphicsPlugin = @import("graphics_plugin");
const InputPlugin = @import("input_plugin");
const TimePlugin = @import("time_plugin");
const sokol = @import("sokol");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, InputPlugin, TimePlugin, Game }, .{});
}

/// Camera controller state
const CameraController = struct {
    // Spherical coordinates for camera orientation
    yaw: f32 = -90.0, // degrees, looking along -Z initially
    pitch: f32 = 0.0, // degrees
    // Movement settings
    move_speed: f32 = 5.0,
    look_sensitivity: f32 = 0.2,
    // Mouse look state
    mouse_captured: bool = true, // enabled by default
};

fn setup(commands: anytype) !void {
    // Initialize camera controller
    commands.setResource(CameraController, .{});

    // Enable mouse capture by default
    sokol.app.showMouse(false);
    sokol.app.lockMouse(true);

    // Set initial camera position
    const camera = commands.getResourcePtrMut(GraphicsPlugin.Camera3D);
    camera.eye = .{ 0, 2, 8 };
    camera.target = .{ 0, 0, 0 };

    // Create a ground plane
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Plane3D{ .width = 20.0, .depth = 20.0, .tiles = 20 },
        Transform{ .x = 0, .y = -1.0, .z = 0 },
        Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1.0 },
    });

    // Create a grid of objects to explore
    // Center cluster - boxes
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 1.0, .height = 2.0, .depth = 1.0 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Color.red,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.8, .height = 0.8, .depth = 0.8 },
        Transform{ .x = 2.0, .y = -0.6, .z = 0 },
        Color.blue,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Box3D{ .width = 0.8, .height = 0.8, .depth = 0.8 },
        Transform{ .x = -2.0, .y = -0.6, .z = 0 },
        Color.green,
    });

    // Spheres at various positions
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Sphere3D{ .radius = 0.5, .slices = 24, .stacks = 18 },
        Transform{ .x = 4.0, .y = -0.5, .z = 3.0 },
        Color.yellow,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Sphere3D{ .radius = 0.7, .slices = 24, .stacks = 18 },
        Transform{ .x = -4.0, .y = -0.3, .z = -3.0 },
        Color{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 }, // orange
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Sphere3D{ .radius = 0.4, .slices = 20, .stacks = 14 },
        Transform{ .x = 0, .y = 1.5, .z = -5.0 },
        Color{ .r = 0.5, .g = 0.0, .b = 1.0, .a = 1.0 }, // purple
    });

    // Cylinders as pillars
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.3, .height = 3.0, .slices = 16 },
        Transform{ .x = 6.0, .y = 0.5, .z = 0 },
        Color{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.3, .height = 3.0, .slices = 16 },
        Transform{ .x = -6.0, .y = 0.5, .z = 0 },
        Color{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.3, .height = 3.0, .slices = 16 },
        Transform{ .x = 0, .y = 0.5, .z = 6.0 },
        Color{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Cylinder3D{ .radius = 0.3, .height = 3.0, .slices = 16 },
        Transform{ .x = 0, .y = 0.5, .z = -6.0 },
        Color{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
    });

    // Torus decorations
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Torus3D{ .radius = 0.6, .ring_radius = 0.15, .sides = 24, .rings = 24 },
        Transform{ .x = 3.0, .y = 0, .z = -4.0 },
        Color{ .r = 0.0, .g = 0.8, .b = 0.8, .a = 1.0 }, // cyan
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Torus3D{ .radius = 0.5, .ring_radius = 0.12, .sides = 24, .rings = 24 },
        Transform{ .x = -3.0, .y = 0, .z = 4.0 },
        Color{ .r = 1.0, .g = 0.0, .b = 0.5, .a = 1.0 }, // pink
    });
}

fn updateCamera(
    camera: ResourceMut(GraphicsPlugin.Camera3D),
    controller: ResourceMut(CameraController),
    keyboard: Resource(InputPlugin.Keyboard),
    mouse: Resource(InputPlugin.Mouse),
    time: Resource(TimePlugin.Time),
) !void {
    const dt = time.value.delta_time;
    const kb = keyboard.value;
    const m = mouse.value;
    var ctrl = controller.value;
    var cam = camera.value;

    // Toggle mouse capture with Tab
    if (kb.isPressed(.TAB)) {
        ctrl.mouse_captured = !ctrl.mouse_captured;
        sokol.app.showMouse(!ctrl.mouse_captured);
        if (ctrl.mouse_captured) {
            sokol.app.lockMouse(true);
        } else {
            sokol.app.lockMouse(false);
        }
    }

    // Mouse look (only when captured)
    if (ctrl.mouse_captured) {
        ctrl.yaw += m.dx * ctrl.look_sensitivity;
        ctrl.pitch -= m.dy * ctrl.look_sensitivity;
        // Clamp pitch to prevent camera flip
        ctrl.pitch = std.math.clamp(ctrl.pitch, -89.0, 89.0);
    }

    // Calculate forward and right vectors from yaw/pitch
    const yaw_rad = std.math.degreesToRadians(ctrl.yaw);
    const pitch_rad = std.math.degreesToRadians(ctrl.pitch);

    const forward = [3]f32{
        @cos(yaw_rad) * @cos(pitch_rad),
        @sin(pitch_rad),
        @sin(yaw_rad) * @cos(pitch_rad),
    };

    // Right vector (perpendicular to forward on XZ plane)
    const right = [3]f32{
        @sin(yaw_rad),
        0,
        -@cos(yaw_rad),
    };

    // Movement
    const speed = ctrl.move_speed * dt;
    var velocity = [3]f32{ 0, 0, 0 };

    // Forward/backward (W/S)
    if (kb.isHeld(.W)) {
        velocity[0] += forward[0] * speed;
        velocity[1] += forward[1] * speed;
        velocity[2] += forward[2] * speed;
    }
    if (kb.isHeld(.S)) {
        velocity[0] -= forward[0] * speed;
        velocity[1] -= forward[1] * speed;
        velocity[2] -= forward[2] * speed;
    }

    // Strafe left/right (A/D)
    if (kb.isHeld(.A)) {
        velocity[0] += right[0] * speed;
        velocity[2] += right[2] * speed;
    }
    if (kb.isHeld(.D)) {
        velocity[0] -= right[0] * speed;
        velocity[2] -= right[2] * speed;
    }

    // Up/down (Space/Left Shift)
    if (kb.isHeld(.SPACE)) {
        velocity[1] += speed;
    }
    if (kb.isHeld(.LEFT_SHIFT)) {
        velocity[1] -= speed;
    }

    // Apply velocity to camera position
    cam.eye[0] += velocity[0];
    cam.eye[1] += velocity[1];
    cam.eye[2] += velocity[2];

    // Update camera target based on forward direction
    cam.target[0] = cam.eye[0] + forward[0];
    cam.target[1] = cam.eye[1] + forward[1];
    cam.target[2] = cam.eye[2] + forward[2];
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};
    pub const Resources = .{CameraController};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = updateCamera, .stage = .pre_update },
        },
    };
};
