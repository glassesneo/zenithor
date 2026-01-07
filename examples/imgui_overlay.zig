/// Example: ImGui Debug Overlay
///
/// Demonstrates ImGui integration for debug UI:
/// - Stats window showing FPS and frame timing from Time plugin
/// - Interactive controls (sliders, checkboxes, buttons)
/// - Animation toggles and shader selection
/// - Window positioning and sizing
///
/// See: plugins/imgui/CLAUDE.md
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const Query = zenithor.Query;
const Shapes3DPlugin = @import("shapes3d_plugin");
const Renderer = @import("renderer_plugin");
const TimePlugin = @import("time_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{Game}, .{});
}

// Tag component for animated objects
const Animated = struct {};

// Debug settings resource
const DebugSettings = struct {
    show_stats: bool = true,
    show_controls: bool = true,
    animate_objects: bool = true,
    animation_speed: f32 = 1.0,
    selected_shader: i32 = 1, // 0=unlit, 1=blinn_phong, 2=pbr
    background_color: [3]f32 = .{ 0.1, 0.1, 0.15 },
};

const Game = struct {
    pub const Requires = .{ Shapes3DPlugin, TimePlugin, ImGuiPlugin };

    pub const Components = .{Animated};
    pub const Resources = .{DebugSettings};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = updateAnimation, .stage = .update },
            .{ .system = applySettings, .stage = .update },
            .{ .system = drawUI, .stage = .render },
        },
    };
};

fn setup(commands: anytype) !void {
    commands.setResource(DebugSettings, .{});

    // Configure 3D camera
    commands.setResource(Shapes3DPlugin.Camera3D, .{
        .eye = .{ 0, 4, 10 },
        .target = .{ 0, 0, 0 },
        .up = .{ 0, 1, 0 },
        .fov = 50.0,
        .near = 0.1,
        .far = 100.0,
    });

    // Ground plane
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Plane3D{ .width = 10.0, .depth = 10.0, .tiles = 5 },
        Transform{ .x = 0, .y = -1.5, .z = 0 },
        Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1.0 },
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    // Animated objects
    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Box3D{ .width = 1.2, .height = 1.2, .depth = 1.2 },
        Transform{ .x = -2.0, .y = 0, .z = 0 },
        Rotation{},
        Color.red,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
        Animated{},
    });

    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Sphere3D{ .radius = 0.8, .slices = 24, .stacks = 18 },
        Transform{ .x = 0, .y = 0, .z = 0 },
        Color.green,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
    });

    _ = try commands.createEntityWith(.{
        Shapes3DPlugin.Torus3D{ .radius = 0.6, .ring_radius = 0.2, .sides = 24, .rings = 24 },
        Transform{ .x = 2.0, .y = 0, .z = 0 },
        Rotation{},
        Color.blue,
        Shapes3DPlugin.Material{ .shader = "blinn_phong" },
        Animated{},
    });
}

fn updateAnimation(
    time: Resource(TimePlugin.Time),
    settings: Resource(DebugSettings),
    animated: Query(struct { Animated, Rotation }),
) void {
    if (!settings.animate_objects) return;

    const dt = time.delta_time * settings.animation_speed;
    for (animated.entities) |entity| {
        if (!animated.filter(entity)) continue;
        const rot = animated.getComponentMut(entity, Rotation);
        rot.y += dt * 0.5;
        rot.x += dt * 0.3;
    }
}

fn applySettings(
    settings: Resource(DebugSettings),
    pass_action: ResourceMut(Renderer.PassAction),
    materials: Query(struct { Shapes3DPlugin.Material }),
) void {
    // Apply background color
    const bg = settings.background_color;
    pass_action.colors[0].clear_value = .{ .r = bg[0], .g = bg[1], .b = bg[2], .a = 1.0 };

    // Apply shader selection
    const shader: []const u8 = switch (settings.selected_shader) {
        0 => "unlit",
        1 => "blinn_phong",
        2 => "pbr",
        else => "blinn_phong",
    };

    for (materials.entities) |entity| {
        if (!materials.filter(entity)) continue;
        const mat = materials.getComponentMut(entity, Shapes3DPlugin.Material);
        mat.shader = shader;
    }
}

fn drawUI(
    time: Resource(TimePlugin.Time),
    settings: ResourceMut(DebugSettings),
    light: ResourceMut(Shapes3DPlugin.Light3D),
    camera: ResourceMut(Shapes3DPlugin.Camera3D),
) void {
    // Stats window
    if (settings.show_stats) {
        ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 250, .y = 180 }, .FirstUseEver);

        var stats_open = settings.show_stats;
        if (ImGuiPlugin.begin("Stats", &stats_open, .None)) {
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Performance");
            ImGuiPlugin.separator();

            // FPS from Time plugin
            ImGuiPlugin.textFmt("FPS: {d:.1}", .{time.fps});
            ImGuiPlugin.textFmt("Frame Time: {d:.2}ms", .{time.delta_time * 1000.0});
            ImGuiPlugin.textFmt("Total Time: {d:.1}s", .{time.total_time});
            ImGuiPlugin.textFmt("Frame: {}", .{time.frame_count});

            ImGuiPlugin.spacing();
            ImGuiPlugin.textFmt("Time Scale: {d:.2}x", .{time.time_scale});
        }
        ImGuiPlugin.end();
        settings.show_stats = stats_open;
    }

    // Controls window
    if (settings.show_controls) {
        ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 200 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 300, .y = 380 }, .FirstUseEver);

        var controls_open = settings.show_controls;
        if (ImGuiPlugin.begin("Debug Controls", &controls_open, .None)) {
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Animation");
            ImGuiPlugin.separator();

            // Checkbox using raw cimgui API
            _ = ig.igCheckbox("Animate Objects", &settings.animate_objects);
            _ = ImGuiPlugin.sliderFloat("Speed", &settings.animation_speed, 0.0, 3.0);

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Shader Selection");
            ImGuiPlugin.separator();

            // Radio buttons using raw cimgui API
            _ = ig.igRadioButtonIntPtr("Unlit", &settings.selected_shader, 0);
            _ = ig.igRadioButtonIntPtr("Blinn-Phong", &settings.selected_shader, 1);
            _ = ig.igRadioButtonIntPtr("PBR", &settings.selected_shader, 2);

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Background");
            ImGuiPlugin.separator();

            // Color picker using raw cimgui API
            _ = ig.igColorEdit3("Color", &settings.background_color, 0);

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Lighting");
            ImGuiPlugin.separator();

            _ = ImGuiPlugin.sliderFloat("Light Y", &light.position[1], 1.0, 10.0);
            _ = ImGuiPlugin.sliderFloat("Ambient", &light.ambient_strength, 0.0, 0.5);

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Camera");
            ImGuiPlugin.separator();

            _ = ImGuiPlugin.sliderFloat("FOV", &camera.fov, 30.0, 90.0);
            _ = ImGuiPlugin.sliderFloat("Distance", &camera.eye[2], 5.0, 20.0);
        }
        ImGuiPlugin.end();
        settings.show_controls = controls_open;
    }

    // Menu bar for toggling windows
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 590 }, .FirstUseEver);
    ImGuiPlugin.setNextWindowSize(.{ .x = 200, .y = 80 }, .FirstUseEver);

    if (ImGuiPlugin.begin("Window Toggles", null, .None)) {
        _ = ig.igCheckbox("Show Stats", &settings.show_stats);
        _ = ig.igCheckbox("Show Controls", &settings.show_controls);
    }
    ImGuiPlugin.end();
}
