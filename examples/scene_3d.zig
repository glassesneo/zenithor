/// Example: 3D Scene Basics
///
/// Demonstrates 3D rendering fundamentals:
/// - Camera3D resource for view/projection control
/// - Light3D resource for scene lighting
/// - Material component with shader selection ("unlit", "blinn_phong", "pbr")
/// - Orbiting camera animation
/// - Interactive shader toggling
///
/// Controls:
///   1/2/3 - Switch shader type (Unlit/Blinn-Phong/PBR)
///   Space - Toggle camera orbit
///
/// See: plugins/shapes3d/CLAUDE.md
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const Query = zenithor.Query;
const Shapes3DPlugin = @import("shapes3d_plugin");
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{Game}, .{});
}

// Demo state resource
const DemoState = struct {
    orbit_enabled: bool = true,
    current_shader: []const u8 = "blinn_phong",
};

const Game = struct {
    pub const Requires = .{ Shapes3DPlugin, TimePlugin, InputPlugin, ImGuiPlugin };

    pub const Components = .{};
    pub const Resources = .{DemoState};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = handleInput, .stage = .update },
            .{ .system = animateCamera, .stage = .update },
            .{ .system = drawUI, .stage = .render },
        },
    };
};

fn setup(commands: anytype) !void {
    commands.setResource(DemoState, .{});

    // Configure Camera3D resource
    commands.setResource(Shapes3DPlugin.Camera3D, .{
        .eye = .{ 0, 3, 8 }, // Camera position
        .target = .{ 0, 0, 0 }, // Look-at point
        .up = .{ 0, 1, 0 }, // Up vector
        .fov = 50.0, // Field of view (degrees)
        .near = 0.1, // Near clipping plane
        .far = 100.0, // Far clipping plane
    });

    // Configure Light3D resource
    commands.setResource(Shapes3DPlugin.Light3D, .{
        .position = .{ 5, 5, 5 },
        .color = .{ 1, 1, 1 },
        .ambient_strength = 0.15,
    });

    // Ground plane
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Plane3D{ .width = 12.0, .depth = 12.0, .tiles = 6 },
        Transform{ .x = 0, .y = -1.5, .z = 0 },
        Color{ .r = 0.35, .g = 0.35, .b = 0.4, .a = 1.0 },
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    // Red sphere (left)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Sphere3D{ .radius = 0.8, .slices = 32, .stacks = 24 },
        Transform{ .x = -2.5, .y = 0, .z = 0 },
        Color.red,
        Shapes3DPlugin.Material{ .shader = "blinn_phong", .shininess = 64.0 },
    });

    // Green box (center)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Box3D{ .width = 1.2, .height = 1.2, .depth = 1.2 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Rotation{},
        Color.green,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    // Blue cylinder (right)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Cylinder3D{ .radius = 0.5, .height = 1.5, .slices = 24 },
        Transform{ .x = 2.5, .y = 0, .z = 0 },
        Color.blue,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    // Yellow torus (above)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Torus3D{ .radius = 0.6, .ring_radius = 0.2, .sides = 24, .rings = 24 },
        Transform{ .x = 0, .y = 2.0, .z = 0 },
        Rotation{},
        Color.yellow,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });
}

fn handleInput(
    keyboard: Resource(InputPlugin.Keyboard),
    demo: ResourceMut(DemoState),
    materials: Query(struct { Shapes3DPlugin.Material }),
) void {
    // Toggle camera orbit
    if (keyboard.isPressed(.SPACE)) {
        demo.orbit_enabled = !demo.orbit_enabled;
    }

    // Shader selection (isPressed for discrete toggle)
    var new_shader: ?[]const u8 = null;
    if (keyboard.isPressed(._1)) new_shader = "unlit";
    if (keyboard.isPressed(._2)) new_shader = "blinn_phong";
    if (keyboard.isPressed(._3)) new_shader = "pbr";

    if (new_shader) |shader| {
        demo.current_shader = shader;
        // Update all materials
        for (materials.entities) |entity| {
            if (!materials.filter(entity)) continue;
            const mat = materials.getComponentMut(entity, Shapes3DPlugin.Material);
            mat.shader = shader;
        }
    }
}

fn animateCamera(
    time: Resource(TimePlugin.Time),
    demo: Resource(DemoState),
    camera: ResourceMut(Shapes3DPlugin.Camera3D),
    rotating: Query(struct { Rotation }),
) void {
    const t = time.total_time;

    // Orbit camera around scene
    if (demo.orbit_enabled) {
        const radius: f32 = 8.0;
        const angle: f32 = @floatCast(t * 0.3);
        camera.eye = .{
            radius * @cos(angle),
            3.0,
            radius * @sin(angle),
        };
    }

    // Rotate objects with Rotation component
    const dt = time.delta_time;
    for (rotating.entities) |entity| {
        if (!rotating.filter(entity)) continue;
        const rot = rotating.getComponentMut(entity, Rotation);
        rot.y += dt * 0.5;
    }
}

fn drawUI(
    demo: Resource(DemoState),
    camera: ResourceMut(Shapes3DPlugin.Camera3D),
    light: ResourceMut(Shapes3DPlugin.Light3D),
) void {
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 320, .y = 420 }, .Once);

    if (ImGuiPlugin.begin("3D Scene Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Shader Types");
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Current: {s}", .{demo.current_shader});
        ImGuiPlugin.bulletText("1 - Unlit (no lighting)");
        ImGuiPlugin.bulletText("2 - Blinn-Phong (classic)");
        ImGuiPlugin.bulletText("3 - PBR (physically-based)");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Camera3D");
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Orbit: {}", .{demo.orbit_enabled});
        ImGuiPlugin.text("Space - Toggle orbit");
        _ = ImGuiPlugin.sliderFloat("Eye Y", &camera.eye[1], 0.5, 10.0);
        _ = ImGuiPlugin.sliderFloat("FOV", &camera.fov, 30.0, 90.0);

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "Light3D");
        ImGuiPlugin.separator();
        _ = ImGuiPlugin.sliderFloat("Light X", &light.position[0], -10.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Light Y", &light.position[1], 0.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Light Z", &light.position[2], -10.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Ambient", &light.ambient_strength, 0.0, 0.5);

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "3D Shapes");
        ImGuiPlugin.separator();
        ImGuiPlugin.bulletText("Plane3D - flat surface");
        ImGuiPlugin.bulletText("Box3D - cube/cuboid");
        ImGuiPlugin.bulletText("Sphere3D - sphere");
        ImGuiPlugin.bulletText("Cylinder3D - cylinder");
        ImGuiPlugin.bulletText("Torus3D - donut shape");
    }
    ImGuiPlugin.end();
}
