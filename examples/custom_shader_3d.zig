/// Example: Custom Shader - Rim/Fresnel Lighting Effect
///
/// Demonstrates how to create and use custom shaders in Zenithor:
/// - Define a custom shader spec module (see examples/shaders/rim.zig)
/// - Register the shader in startup via ShaderRegistry.register()
/// - Use the shader name in Material.shader
///
/// The rim shader creates a glowing edge effect (Fresnel) that's commonly used for:
/// - Sci-fi effects (force fields, energy shields)
/// - Selection highlighting
/// - Stylized/toon rendering
///
/// Controls:
///   1/2/3/4 - Switch shader (Unlit/Blinn-Phong/PBR/Rim)
///   Space - Toggle camera orbit
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

// Custom shader spec - defines shader interface
const RimShader = @import("rim_spec");

pub fn main() !void {
    zenithor.run(.{Game}, .{});
}

// Demo state resource
const DemoState = struct {
    orbit_enabled: bool = true,
    current_shader: []const u8 = "rim", // Start with custom shader to showcase it
};

const Game = struct {
    pub const Requires = .{ Shapes3DPlugin, TimePlugin, InputPlugin, ImGuiPlugin };

    pub const Components = .{};
    pub const Resources = .{DemoState};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = registerCustomShaders, .stage = .first },
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = handleInput, .stage = .update },
            .{ .system = animateCamera, .stage = .update },
            .{ .system = drawUI, .stage = .render },
        },
    };
};

/// Register custom shaders with the ShaderRegistry.
/// IMPORTANT: This runs at .first stage, after Shapes3DPlugin's init has set up
/// the registry's layout and depth_state. Plugin order in zenithor.run() matters:
/// Shapes3DPlugin must come before Game for correct initialization order.
fn registerCustomShaders(registry: ResourceMut(Shapes3DPlugin.ShaderRegistry)) void {
    // Register our custom rim shader
    // The shader spec module must implement: name, shaderDesc, pipelineDesc, applyVsUniforms, applyFsUniforms
    registry.register(RimShader);
}

fn setup(commands: anytype) !void {
    commands.setResource(DemoState, .{});

    // Configure Camera3D resource
    commands.setResource(Shapes3DPlugin.Camera3D, .{
        .eye = .{ 0, 3, 8 },
        .target = .{ 0, 0, 0 },
        .up = .{ 0, 1, 0 },
        .fov = 50.0,
        .near = 0.1,
        .far = 100.0,
    });

    // Configure Light3D
    commands.setResource(Shapes3DPlugin.Light3D, .{
        .position = .{ 5, 5, 5 },
        .color = .{ 1, 1, 1 },
        .ambient_strength = 0.1,
    });

    // Ground plane (dark, using blinn_phong)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Plane3D{ .width = 12.0, .depth = 12.0, .tiles = 6 },
        Transform{ .x = 0, .y = -1.5, .z = 0 },
        Color{ .r = 0.2, .g = 0.2, .b = 0.25, .a = 1.0 },
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    // Central sphere with rim shader (cyan rim on dark surface)
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Sphere3D{ .radius = 1.0, .slices = 32, .stacks = 24 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Color{ .r = 0.1, .g = 0.8, .b = 1.0, .a = 1.0 }, // Cyan rim color
        Shapes3DPlugin.Material{
            .shader = "rim",
            .shininess = 3.0, // rim_power: controls falloff (higher = thinner rim)
            .specular_strength = 1.5, // rim_intensity: controls brightness
        },
    });

    // Left sphere - red rim with softer falloff
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Sphere3D{ .radius = 0.7, .slices = 24, .stacks = 18 },
        Transform{ .x = -2.5, .y = 0, .z = 0 },
        Color.red,
        Shapes3DPlugin.Material{ .shader = "rim", .shininess = 2.0, .specular_strength = 1.0 },
    });

    // Right sphere - rim shader with different parameters
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Sphere3D{ .radius = 0.7, .slices = 24, .stacks = 18 },
        Transform{ .x = 2.5, .y = 0, .z = 0 },
        Color{ .r = 0.2, .g = 1.0, .b = 0.3, .a = 1.0 }, // Green rim
        Shapes3DPlugin.Material{
            .shader = "rim",
            .shininess = 5.0, // Sharper rim
            .specular_strength = 2.0, // Brighter
        },
    });

    // Rotating torus above
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Torus3D{ .radius = 0.5, .ring_radius = 0.15, .sides = 24, .rings = 24 },
        Transform{ .x = 0, .y = 1.8, .z = 0 },
        Rotation{},
        Color{ .r = 1.0, .g = 0.5, .b = 0.8, .a = 1.0 }, // Pink rim
        Shapes3DPlugin.Material{ .shader = "rim", .shininess = 2.5, .specular_strength = 1.2 },
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

    // Shader selection
    var new_shader: ?[]const u8 = null;
    if (keyboard.isPressed(._1)) new_shader = "unlit";
    if (keyboard.isPressed(._2)) new_shader = "blinn_phong";
    if (keyboard.isPressed(._3)) new_shader = "pbr";
    if (keyboard.isPressed(._4)) new_shader = "rim";

    if (new_shader) |shader| {
        demo.current_shader = shader;
        // Update all materials (except ground plane which stays blinn_phong)
        for (materials.entities) |entity| {
            if (!materials.filter(entity)) continue;
            const mat = materials.getComponentMut(entity, Shapes3DPlugin.Material);
            // Skip ground plane (it has low shininess, keep it blinn_phong)
            if (mat.shininess < 1.5) continue;
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

    // Rotate torus
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
    ImGuiPlugin.setNextWindowSize(.{ .x = 340, .y = 480 }, .Once);

    if (ImGuiPlugin.begin("Custom Shader Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Custom Rim Shader");
        ImGuiPlugin.separator();
        ImGuiPlugin.textWrapped("The rim shader creates a Fresnel edge glow effect. Surfaces facing away from the camera appear brighter.");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Shader Selection");
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Current: {s}", .{demo.current_shader});
        ImGuiPlugin.bulletText("1 - Unlit");
        ImGuiPlugin.bulletText("2 - Blinn-Phong");
        ImGuiPlugin.bulletText("3 - PBR");
        ImGuiPlugin.bulletText("4 - Rim (custom)");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 0.8, .y = 0.5, .z = 1.0, .w = 1.0 }, "Rim Shader Parameters");
        ImGuiPlugin.separator();
        ImGuiPlugin.bulletText("shininess -> rim_power");
        ImGuiPlugin.textWrapped("  Higher = thinner rim edge");
        ImGuiPlugin.bulletText("specular_strength -> rim_intensity");
        ImGuiPlugin.textWrapped("  Higher = brighter rim glow");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "Camera/Light");
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Orbit: {}", .{demo.orbit_enabled});
        ImGuiPlugin.text("Space - Toggle orbit");
        _ = ImGuiPlugin.sliderFloat("Eye Y", &camera.eye[1], 0.5, 10.0);
        _ = ImGuiPlugin.sliderFloat("Light Y", &light.position[1], 0.0, 10.0);
        _ = ImGuiPlugin.sliderFloat("Ambient", &light.ambient_strength, 0.0, 0.3);
    }
    ImGuiPlugin.end();
}
