/// Demo: Shader Comparison
///
/// This example demonstrates the three built-in shader types:
/// - Unlit: Simple vertex color rendering without lighting
/// - Blinn-Phong: Classic diffuse + specular lighting
/// - PBR: Physically-based rendering with metallic/roughness
///
/// Each row shows the same shapes rendered with different shaders,
/// allowing direct visual comparison of lighting models.
const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Color = zenithor.Color;
const ResourceMut = zenithor.ResourceMut;
const Resource = zenithor.Resource;
const Query = zenithor.Query;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;
const TimePlugin = @import("time_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, ImGuiPlugin, Game }, .{});
}

// Tag components for animation
const RotatingShape = struct {};

// Demo state
const DemoState = struct {
    time: f32 = 0,
    rotate_objects: bool = true,
    light_orbit: bool = true,
};

fn setup(commands: anytype) !void {
    const colors = [_]Color{
        Color.red,
        Color.green,
        Color.blue,
        Color.yellow,
    };

    const shader_types = [_]GraphicsPlugin.ShaderType{ .unlit, .blinn_phong, .pbr };

    // Create 3 rows (one per shader) x 4 columns (one per shape)
    inline for (shader_types, 0..) |shader, row| {
        const y: f32 = 2.0 - @as(f32, @floatFromInt(row)) * 2.0; // Row positions: 2, 0, -2

        // Sphere
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.8, .slices = 32, .stacks = 24 },
            Transform{ .x = -4.5, .y = y, .z = 0 },
            colors[0],
            GraphicsPlugin.Material{ .shader = shader },
        });

        // Box (rotating)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Box3D{ .width = 1.2, .height = 1.2, .depth = 1.2 },
            Transform{ .x = -1.5, .y = y, .z = 0 },
            Rotation{},
            colors[1],
            GraphicsPlugin.Material{ .shader = shader },
            RotatingShape{},
        });

        // Cylinder
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.6, .height = 1.4, .slices = 24 },
            Transform{ .x = 1.5, .y = y, .z = 0 },
            colors[2],
            GraphicsPlugin.Material{ .shader = shader },
        });

        // Torus (rotating)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Torus3D{ .radius = 0.6, .ring_radius = 0.25, .sides = 24, .rings = 24 },
            Transform{ .x = 4.5, .y = y, .z = 0 },
            Rotation{},
            colors[3],
            GraphicsPlugin.Material{ .shader = shader },
            RotatingShape{},
        });
    }

    // Ground plane
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Plane3D{ .width = 20.0, .depth = 12.0, .tiles = 10 },
        Transform{ .x = 0, .y = -4.0, .z = 0 },
        Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1.0 },
        GraphicsPlugin.Material{ .shader = .blinn_phong },
    });

    // Initialize state and camera
    commands.setResource(DemoState, .{});

    // Set initial camera position
    commands.setResource(GraphicsPlugin.Camera3D, .{
        .eye = .{ 0, 4, 14 },
        .target = .{ 0, 0, 0 },
        .up = .{ 0, 1, 0 },
        .fov = 50.0,
        .near = 0.1,
        .far = 100.0,
    });
}

fn updateAnimation(
    demo: ResourceMut(DemoState),
    time: Resource(TimePlugin.Time),
    light: ResourceMut(GraphicsPlugin.Light3D),
    rotating: Query(struct { RotatingShape, Rotation }),
) void {
    demo.value.time += time.value.delta_time;

    // Orbit light around scene
    if (demo.value.light_orbit) {
        const radius: f32 = 8.0;
        const angle = demo.value.time * 0.5;
        light.value.position = .{
            radius * @cos(angle),
            5.0,
            radius * @sin(angle),
        };
    }

    // Rotate tagged objects
    if (demo.value.rotate_objects) {
        const rot_speed = time.value.delta_time;
        for (rotating.entities) |entity| {
            if (!rotating.filter(entity)) continue;
            const rot = rotating.getComponentMut(entity, Rotation);
            rot.x += rot_speed * 0.5;
            rot.y += rot_speed * 0.7;
        }
    }
}

fn drawUI(
    demo: ResourceMut(DemoState),
    light: ResourceMut(GraphicsPlugin.Light3D),
    camera: ResourceMut(GraphicsPlugin.Camera3D),
) void {
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 10 }, .FirstUseEver);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 320, .y = 500 }, .FirstUseEver);

    if (ImGuiPlugin.begin("Shader Comparison", null, .None)) {
        ImGuiPlugin.textWrapped("Compare the three built-in shaders:");
        ImGuiPlugin.spacing();
        ImGuiPlugin.bulletText("Top row: Unlit (no lighting)");
        ImGuiPlugin.bulletText("Middle row: Blinn-Phong");
        ImGuiPlugin.bulletText("Bottom row: PBR");

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Animation");
        // Use raw imgui for checkboxes (not wrapped in ImGuiPlugin)
        _ = ig.igCheckbox("Rotate Objects", &demo.value.rotate_objects);
        _ = ig.igCheckbox("Orbit Light", &demo.value.light_orbit);

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Light Position");
        _ = ImGuiPlugin.sliderFloat("Light X", &light.value.position[0], -10.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Light Y", &light.value.position[1], -10.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Light Z", &light.value.position[2], -10.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Ambient", &light.value.ambient_strength, 0.0, 1.0);

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Camera");
        _ = ImGuiPlugin.sliderFloat("Eye X", &camera.value.eye[0], -20.0, 20.0);
        _ = ImGuiPlugin.sliderFloat("Eye Y", &camera.value.eye[1], -20.0, 20.0);
        _ = ImGuiPlugin.sliderFloat("Eye Z", &camera.value.eye[2], -20.0, 20.0);
        _ = ImGuiPlugin.sliderFloat("FOV", &camera.value.fov, 20.0, 120.0);

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Shader Details:");
        ImGuiPlugin.spacing();
        ImGuiPlugin.textWrapped("UNLIT: Renders vertex colors directly without lighting. Good for UI and debug.");
        ImGuiPlugin.spacing();
        ImGuiPlugin.textWrapped("BLINN-PHONG: Classic lighting with ambient, diffuse, and specular.");
        ImGuiPlugin.spacing();
        ImGuiPlugin.textWrapped("PBR: Physically-based with metallic/roughness workflow.");
    }
    ImGuiPlugin.end();
}

const Game = struct {
    pub const Components = .{RotatingShape};
    pub const Events = .{};
    pub const Resources = .{DemoState};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = updateAnimation, .stage = .update },
            .{ .system = drawUI, .stage = .update },
        },
    };
};
