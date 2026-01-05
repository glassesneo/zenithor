/// Example: Comprehensive 3D Showcase
///
/// This example demonstrates ALL major features of Zenithor:
///
/// CORE ENGINE:
/// - zenithor.run() with plugin tuple and automatic dependency expansion
/// - BuiltinPlugin components (Transform, Color, Rotation, Scale)
/// - System scheduling with stages, priority, tags, before/after constraints
/// - Error handling with GameLoopError/EventLoopError events
///
/// GRAPHICS PLUGIN:
/// - All 3D shapes: Plane3D, Box3D, Sphere3D, Cylinder3D, Torus3D
/// - Camera3D resource with orbit/fly controls
/// - Light3D resource with position and ambient
/// - Material component with shader selection (.unlit, .blinn_phong, .pbr)
/// - PassAction resource for background color
///
/// TIME PLUGIN:
/// - delta_time for frame-rate independent movement
/// - time_scale for pause/slow-motion
/// - fps tracking and total_time
///
/// INPUT PLUGIN:
/// - Keyboard: isPressed/isHeld/isReleased/heldFrames
/// - Mouse: position, delta, buttons, scroll
///
/// IMGUI PLUGIN:
/// - Debug windows with stats, controls, help
/// - Sliders, checkboxes, buttons, color pickers
/// - Window positioning and sizing
///
/// SERIALIZATION PLUGIN:
/// - Save/load game state with F5/F9
/// - Resource and entity persistence
///
/// PLUGIN AUTHORING:
/// - Custom plugin with Components/Resources/Events
/// - Plugin dependencies via pub const Requires
/// - Declarative system registration
///
/// Controls:
///   Mouse - Look around (1st person)
///   Left Click - Spawn selected shape
///   Mouse Wheel - Zoom in/out (orbit mode)
///   WASD - Move camera (both modes)
///   QE - Up/Down (fly mode) or Zoom (orbit mode)
///   Arrow keys - Alternative look/orbit controls
///   Space - Toggle orbit/fly camera mode
///   Tab - Toggle mouse capture
///   1/2/3 - Switch shader (Unlit/Blinn-Phong/PBR)
///   4/5/6/7 - Select shape (Box/Sphere/Cylinder/Torus)
///   P - Toggle pause (time_scale)
///   +/- - Adjust time scale
///   R - Reset camera
///   F5 - Save game
///   F9 - Load game
///   F1 - Toggle help window
///   Escape - Toggle pause
const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Scale = zenithor.Scale;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const Query = zenithor.Query;
const SingleQuery = zenithor.SingleQuery;
const EventWriter = zenithor.EventWriter;
const EventReader = zenithor.EventReader;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const Stage = zenithor.Stage;
const GraphicsPlugin = @import("graphics_plugin").Default;
const RenderContext = @import("render_context_plugin");
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const SerializationPlugin = @import("serialization_plugin");
const sokol = @import("sokol");
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    // All plugins included - dependencies auto-expanded
    zenithor.run(.{
        GraphicsPlugin,
        TimePlugin,
        InputPlugin,
        ImGuiPlugin,
        SerializationPlugin,
        PhysicsPlugin, // Custom plugin demonstrating plugin authoring
        GamePlugin, // Main game plugin
    }, .{});
}

// =============================================================================
// CUSTOM PHYSICS PLUGIN - Demonstrates plugin authoring with Requires
// =============================================================================
const PhysicsPlugin = struct {
    // Declare dependency - TimePlugin will be auto-included
    pub const Requires = .{TimePlugin};

    // Component: Velocity for movement
    pub const Velocity = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
    };

    // Component: Angular velocity for rotation
    pub const AngularVelocity = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
    };

    // Resource: Physics configuration
    pub const PhysicsConfig = struct {
        gravity: f32 = -9.8,
        damping: f32 = 0.98,
        enabled: bool = true,
    };

    // Event: Collision notification
    pub const CollisionEvent = struct {
        entity_a: u32,
        entity_b: u32,
    };

    pub const Components = .{ Velocity, AngularVelocity };
    pub const Resources = .{PhysicsConfig};
    pub const Events = .{CollisionEvent};

    pub const systems = .{
        .startup = &.{
            .{ .system = initPhysics, .stage = .first },
        },
        .main = &.{
            // Physics runs in update stage with specific priority
            .{
                .system = applyVelocity,
                .stage = .update,
                .config = .{
                    .priority = -10, // Run early in update
                    .tags = &.{"physics"},
                },
            },
            .{ .system = applyAngularVelocity, .stage = .update, .config = .{
                .priority = -10,
                .tags = &.{"physics"},
            } },
            .{
                .system = applyDamping,
                .stage = .update,
                .config = .{
                    .priority = -5,
                    .after = &.{"physics"}, // Run after physics systems
                },
            },
        },
    };

    fn initPhysics(commands: anytype) void {
        commands.setResource(PhysicsConfig, .{
            .gravity = -9.8,
            .damping = 0.98,
            .enabled = true,
        });
    }

    fn applyVelocity(
        time: Resource(TimePlugin.Time),
        config: Resource(PhysicsConfig),
        moving: Query(struct { Transform, Velocity }),
    ) void {
        if (!config.enabled) return;
        const dt = time.delta_time * time.time_scale;

        for (moving.entities) |entity| {
            if (!moving.filter(entity)) continue;
            const transform = moving.getComponentMut(entity, Transform);
            const vel = moving.getComponent(entity, Velocity);

            transform.x += vel.x * dt;
            transform.y += vel.y * dt;
            transform.z += vel.z * dt;
        }
    }

    fn applyAngularVelocity(
        time: Resource(TimePlugin.Time),
        config: Resource(PhysicsConfig),
        rotating: Query(struct { Rotation, AngularVelocity }),
    ) void {
        if (!config.enabled) return;
        const dt = time.delta_time * time.time_scale;

        for (rotating.entities) |entity| {
            if (!rotating.filter(entity)) continue;
            const rot = rotating.getComponentMut(entity, Rotation);
            const ang_vel = rotating.getComponent(entity, AngularVelocity);

            rot.x += ang_vel.x * dt;
            rot.y += ang_vel.y * dt;
            rot.z += ang_vel.z * dt;
        }
    }

    fn applyDamping(
        config: Resource(PhysicsConfig),
        velocities: SingleQuery(Velocity),
        angular_velocities: SingleQuery(AngularVelocity),
    ) void {
        if (!config.enabled) return;
        const damping = config.damping;

        for (velocities.components) |*vel| {
            vel.x *= damping;
            vel.y *= damping;
            vel.z *= damping;
        }

        for (angular_velocities.components) |*ang_vel| {
            ang_vel.x *= damping;
            ang_vel.y *= damping;
            ang_vel.z *= damping;
        }
    }
};

// =============================================================================
// MAIN GAME PLUGIN
// =============================================================================
const GamePlugin = struct {
    pub const Requires = .{PhysicsPlugin};

    // Tag components for entity identification
    pub const Interactable = struct {};
    pub const Orbiting = struct { center_x: f32, center_y: f32, center_z: f32, radius: f32, speed: f32 };
    pub const Bouncing = struct { min_y: f32, max_y: f32 };
    pub const Pulsing = struct { min_scale: f32, max_scale: f32, speed: f32 };

    // Game state resource
    pub const GameState = struct {
        camera_mode: CameraMode = .fly, // Default to 1st person perspective
        show_help: bool = true,
        show_stats: bool = true,
        show_controls: bool = true,
        show_scene: bool = true,
        wireframe_mode: bool = false,
        selected_shader: GraphicsPlugin.ShaderType = .blinn_phong,
        // Fly mode: yaw/pitch for direct camera control
        yaw: f32 = std.math.pi, // Face -Z direction (toward scene center)
        pitch: f32 = -0.3, // Slightly looking down
        // Orbit mode: angle around target
        orbit_angle: f32 = 0,
        orbit_pitch: f32 = 0.3,
        orbit_distance: f32 = 15,
        entity_count: u32 = 0,
        paused: bool = false,
        mouse_captured: bool = true, // Mouse captured for 1st person look (true = hidden and captured)
        // Scaled animation time (respects time_scale/pause)
        animation_time: f32 = 0,
        // Shape spawning
        selected_shape: ShapeType = .box,
        spawn_count: u32 = 0,
    };

    pub const CameraMode = enum { orbit, fly };
    pub const ShapeType = enum { box, sphere, cylinder, torus };

    // Scene statistics
    pub const SceneStats = struct {
        boxes: u32 = 0,
        spheres: u32 = 0,
        cylinders: u32 = 0,
        tori: u32 = 0,
        total_triangles: u32 = 0,
    };

    pub const Components = .{ Interactable, Orbiting, Bouncing, Pulsing };
    pub const Resources = .{ GameState, SceneStats };
    pub const Events = .{ BuiltinPlugin.GameLoopError, BuiltinPlugin.EventLoopError };

    pub const systems = .{
        .startup = &.{
            .{ .system = setupScene, .stage = .first },
        },
        .main = &.{
            // Input handling - runs first
            .{ .system = handleInput, .stage = .pre_update, .config = .{ .priority = -100 } },
            // Update animation time (respects time_scale)
            .{ .system = updateAnimationTime, .stage = .update, .config = .{ .priority = -50, .tags = &.{"time"} } },
            // Animations - run in update stage after time update
            .{ .system = updateOrbiting, .stage = .update, .config = .{ .tags = &.{"animation"}, .after = &.{"time"} } },
            .{ .system = updateBouncing, .stage = .update, .config = .{ .tags = &.{"animation"}, .after = &.{"time"} } },
            .{ .system = updatePulsing, .stage = .update, .config = .{ .tags = &.{"animation"}, .after = &.{"time"} } },
            // Camera update - after animations
            .{ .system = updateCamera, .stage = .update, .config = .{ .after = &.{"animation"} } },
            // Error monitoring
            .{ .system = monitorErrors, .stage = .post_update },
            // UI - render stage
            .{ .system = drawHelpWindow, .stage = .render },
            .{ .system = drawStatsWindow, .stage = .render },
            .{ .system = drawControlsWindow, .stage = .render },
            .{ .system = drawSceneWindow, .stage = .render },
        },
    };

    fn setupScene(
        commands: anytype,
        pass_action: ResourceMut(RenderContext.PassAction),
    ) !void {
        // Initialize resources
        commands.setResource(GameState, .{});
        commands.setResource(SceneStats, .{});

        // Hide and lock mouse cursor for 1st person camera
        sokol.app.showMouse(false);
        sokol.app.lockMouse(true);

        // Set background color
        pass_action.colors[0].clear_value = .{ .r = 0.05, .g = 0.05, .b = 0.1, .a = 1.0 };

        // Configure camera
        commands.setResource(GraphicsPlugin.Camera3D, .{
            .eye = .{ 0, 5, 15 },
            .target = .{ 0, 0, 0 },
            .up = .{ 0, 1, 0 },
            .fov = 60.0,
            .near = 0.1,
            .far = 200.0,
        });

        // Configure lighting
        commands.setResource(GraphicsPlugin.Light3D, .{
            .position = .{ 10, 15, 10 },
            .color = .{ 1, 0.95, 0.9 },
            .ambient_strength = 0.15,
        });

        // === GROUND PLANE ===
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Plane3D{ .width = 50.0, .depth = 50.0, .tiles = 25 },
            Transform{ .x = 0, .y = -2, .z = 0 },
            Color{ .r = 0.2, .g = 0.25, .b = 0.3, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong },
        });

        // === CENTRAL STRUCTURE ===
        // Large central sphere
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 1.5, .slices = 48, .stacks = 36 },
            Transform{ .x = 0, .y = 0, .z = 0 },
            Rotation{},
            Color{ .r = 0.9, .g = 0.7, .b = 0.2, .a = 1.0 }, // Gold
            GraphicsPlugin.Material{ .shader = .pbr, .metallic = 0.9, .roughness = 0.1 },
            PhysicsPlugin.AngularVelocity{ .y = 0.2 },
            Interactable{},
        });

        // === ORBITING OBJECTS ===
        // Red orbiting box
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Box3D{ .width = 0.8, .height = 0.8, .depth = 0.8 },
            Transform{ .x = 4, .y = 0, .z = 0 },
            Rotation{},
            Color.red,
            GraphicsPlugin.Material{ .shader = .blinn_phong, .shininess = 64.0 },
            PhysicsPlugin.AngularVelocity{ .x = 1.0, .y = 0.5 },
            Orbiting{ .center_x = 0, .center_y = 0, .center_z = 0, .radius = 4, .speed = 0.5 },
            Interactable{},
        });

        // Green orbiting sphere
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.5, .slices = 24, .stacks = 18 },
            Transform{ .x = 0, .y = 0, .z = 5 },
            Color.green,
            GraphicsPlugin.Material{ .shader = .blinn_phong },
            Orbiting{ .center_x = 0, .center_y = 0, .center_z = 0, .radius = 5, .speed = -0.3 },
            Interactable{},
        });

        // Blue orbiting torus
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Torus3D{ .radius = 0.6, .ring_radius = 0.2, .sides = 24, .rings = 24 },
            Transform{ .x = 6, .y = 1, .z = 0 },
            Rotation{},
            Color.blue,
            GraphicsPlugin.Material{ .shader = .blinn_phong },
            PhysicsPlugin.AngularVelocity{ .x = 0.3, .z = 0.5 },
            Orbiting{ .center_x = 0, .center_y = 1, .center_z = 0, .radius = 6, .speed = 0.2 },
            Interactable{},
        });

        // === BOUNCING OBJECTS ===
        // Cyan bouncing cylinder
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.4, .height = 1.0, .slices = 20 },
            Transform{ .x = -5, .y = 0, .z = 3 },
            Color.cyan,
            GraphicsPlugin.Material{ .shader = .blinn_phong },
            Bouncing{ .min_y = -1.5, .max_y = 2.0 },
            Interactable{},
        });

        // Magenta bouncing sphere
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 24, .stacks = 18 },
            Transform{ .x = 5, .y = 0, .z = -3 },
            Color.magenta,
            GraphicsPlugin.Material{ .shader = .pbr, .metallic = 0.3, .roughness = 0.4 },
            Bouncing{ .min_y = -1.5, .max_y = 3.0 },
            Interactable{},
        });

        // === PULSING OBJECTS ===
        // White pulsing box
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Box3D{ .width = 1.0, .height = 1.0, .depth = 1.0 },
            Transform{ .x = -6, .y = 0, .z = -5 },
            Rotation{},
            Scale{ .x = 1, .y = 1, .z = 1 },
            Color.white,
            GraphicsPlugin.Material{ .shader = .unlit },
            PhysicsPlugin.AngularVelocity{ .y = 0.8 },
            Pulsing{ .min_scale = 0.5, .max_scale = 1.5, .speed = 2.0 },
            Interactable{},
        });

        // Orange pulsing torus
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Torus3D{ .radius = 0.8, .ring_radius = 0.25, .sides = 32, .rings = 32 },
            Transform{ .x = 6, .y = 0, .z = -5 },
            Rotation{},
            Scale{ .x = 1, .y = 1, .z = 1 },
            Color.orange,
            GraphicsPlugin.Material{ .shader = .pbr, .metallic = 0.7, .roughness = 0.2 },
            PhysicsPlugin.AngularVelocity{ .x = 0.5, .y = 0.3 },
            Pulsing{ .min_scale = 0.7, .max_scale = 1.3, .speed = 1.5 },
            Interactable{},
        });

        // === STATIC DECORATIONS ===
        // Corner pillars (manually unrolled since createEntityWith requires comptime args)

        // Pillar 1: Red (-8, -8)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.5, .height = 4.0, .slices = 16 },
            Transform{ .x = -8, .y = 0, .z = -8 },
            Color{ .r = 0.8, .g = 0.2, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong, .shininess = 32.0 },
        });
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 16, .stacks = 12 },
            Transform{ .x = -8, .y = 2.3, .z = -8 },
            Color{ .r = 0.8, .g = 0.2, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong },
        });

        // Pillar 2: Green (-8, 8)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.5, .height = 4.0, .slices = 16 },
            Transform{ .x = -8, .y = 0, .z = 8 },
            Color{ .r = 0.2, .g = 0.8, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong, .shininess = 32.0 },
        });
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 16, .stacks = 12 },
            Transform{ .x = -8, .y = 2.3, .z = 8 },
            Color{ .r = 0.2, .g = 0.8, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong },
        });

        // Pillar 3: Blue (8, -8)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.5, .height = 4.0, .slices = 16 },
            Transform{ .x = 8, .y = 0, .z = -8 },
            Color{ .r = 0.2, .g = 0.2, .b = 0.8, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong, .shininess = 32.0 },
        });
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 16, .stacks = 12 },
            Transform{ .x = 8, .y = 2.3, .z = -8 },
            Color{ .r = 0.2, .g = 0.2, .b = 0.8, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong },
        });

        // Pillar 4: Yellow (8, 8)
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Cylinder3D{ .radius = 0.5, .height = 4.0, .slices = 16 },
            Transform{ .x = 8, .y = 0, .z = 8 },
            Color{ .r = 0.8, .g = 0.8, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong, .shininess = 32.0 },
        });
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Sphere3D{ .radius = 0.6, .slices = 16, .stacks = 12 },
            Transform{ .x = 8, .y = 2.3, .z = 8 },
            Color{ .r = 0.8, .g = 0.8, .b = 0.2, .a = 1.0 },
            GraphicsPlugin.Material{ .shader = .blinn_phong },
        });

        // Arch between pillars
        _ = try commands.createEntityWith(.{
            GraphicsPlugin.Torus3D{ .radius = 2.0, .ring_radius = 0.3, .sides = 32, .rings = 48 },
            Transform{ .x = 0, .y = 4, .z = -8 },
            Rotation{ .x = std.math.pi / 2.0 },
            Color{ .r = 0.6, .g = 0.4, .b = 0.8, .a = 1.0 }, // Purple
            GraphicsPlugin.Material{ .shader = .pbr, .metallic = 0.5, .roughness = 0.3 },
        });

        std.debug.print("\n=== ZENITHOR 3D SHOWCASE ===\n", .{});
        std.debug.print("Press F1 to toggle help\n", .{});
        std.debug.print("Press WASD/QE to fly, Arrows to orbit\n", .{});
        std.debug.print("Press 1/2/3 to change shaders\n", .{});
        std.debug.print("Press F5/F9 to save/load\n\n", .{});
    }

    fn handleInput(
        keyboard: Resource(InputPlugin.Keyboard),
        mouse: Resource(InputPlugin.Mouse),
        time: ResourceMut(TimePlugin.Time),
        game: ResourceMut(GameState),
        camera: Resource(GraphicsPlugin.Camera3D),
        save_file: ResourceMut(SerializationPlugin.SaveFile),
        materials: Query(struct { GraphicsPlugin.Material }),
        commands: anytype,
    ) !void {
        // Tab - Toggle mouse capture
        if (keyboard.isPressed(.TAB)) {
            game.mouse_captured = !game.mouse_captured;
            sokol.app.showMouse(!game.mouse_captured);
            sokol.app.lockMouse(game.mouse_captured);
        }

        // F1 - Toggle help
        if (keyboard.isPressed(.F1)) {
            game.show_help = !game.show_help;
        }

        // Escape - Could be used for menu
        if (keyboard.isPressed(.ESCAPE)) {
            // In a real game, might show pause menu
            game.paused = !game.paused;
        }

        // Space - Toggle camera mode
        if (keyboard.isPressed(.SPACE)) {
            game.camera_mode = switch (game.camera_mode) {
                .orbit => .fly,
                .fly => .orbit,
            };
        }

        // P - Toggle pause
        if (keyboard.isPressed(.P)) {
            game.paused = !game.paused;
            time.time_scale = if (game.paused) 0.0 else 1.0;
        }

        // +/- Adjust time scale
        if (keyboard.isPressed(.EQUAL) or keyboard.isPressed(.KP_ADD)) {
            time.time_scale = @min(3.0, time.time_scale + 0.25);
            game.paused = false;
        }
        if (keyboard.isPressed(.MINUS) or keyboard.isPressed(.KP_SUBTRACT)) {
            time.time_scale = @max(0.0, time.time_scale - 0.25);
            if (time.time_scale == 0.0) game.paused = true;
        }

        // 1/2/3 - Shader selection
        if (keyboard.isPressed(._1)) {
            game.selected_shader = .unlit;
            updateAllMaterials(materials, .unlit);
        }
        if (keyboard.isPressed(._2)) {
            game.selected_shader = .blinn_phong;
            updateAllMaterials(materials, .blinn_phong);
        }
        if (keyboard.isPressed(._3)) {
            game.selected_shader = .pbr;
            updateAllMaterials(materials, .pbr);
        }

        // 4/5/6/7 - Shape selection for spawning
        if (keyboard.isPressed(._4)) game.selected_shape = .box;
        if (keyboard.isPressed(._5)) game.selected_shape = .sphere;
        if (keyboard.isPressed(._6)) game.selected_shape = .cylinder;
        if (keyboard.isPressed(._7)) game.selected_shape = .torus;

        // Left click - Spawn shape in front of camera
        if (mouse.isPressed(.LEFT)) {
            // Calculate spawn position: 5 units in front of camera
            const cos_pitch = @cos(game.yaw);
            const sin_pitch = @sin(game.yaw);
            const spawn_dist: f32 = 5.0;
            const spawn_x = camera.eye[0] + sin_pitch * spawn_dist;
            const spawn_y = camera.eye[1];
            const spawn_z = camera.eye[2] + cos_pitch * spawn_dist;

            // Random-ish color based on spawn count
            const hue = @as(f32, @floatFromInt(game.spawn_count * 37 % 360)) / 360.0;
            const color = hueToRgb(hue);

            // Random-ish angular velocity
            const ang_x = @sin(@as(f32, @floatFromInt(game.spawn_count)) * 1.1) * 2.0;
            const ang_y = @cos(@as(f32, @floatFromInt(game.spawn_count)) * 1.3) * 2.0;
            const ang_z = @sin(@as(f32, @floatFromInt(game.spawn_count)) * 1.7) * 1.0;

            // Create entity and add components with runtime values
            const entity = commands.createEntity();
            try commands.addComponent(entity, Transform, .{ .x = spawn_x, .y = spawn_y, .z = spawn_z });
            try commands.addComponent(entity, Color, color);
            try commands.addComponent(entity, GraphicsPlugin.Material, .{ .shader = game.selected_shader });
            try commands.addTag(entity, Interactable);

            switch (game.selected_shape) {
                .box => {
                    try commands.addComponent(entity, GraphicsPlugin.Box3D, .{ .width = 0.8, .height = 0.8, .depth = 0.8 });
                    try commands.addComponent(entity, Rotation, .{});
                    try commands.addComponent(entity, PhysicsPlugin.AngularVelocity, .{ .x = ang_x, .y = ang_y, .z = ang_z });
                },
                .sphere => {
                    try commands.addComponent(entity, GraphicsPlugin.Sphere3D, .{ .radius = 0.5, .slices = 24, .stacks = 18 });
                },
                .cylinder => {
                    try commands.addComponent(entity, GraphicsPlugin.Cylinder3D, .{ .radius = 0.4, .height = 1.0, .slices = 20 });
                    try commands.addComponent(entity, Rotation, .{});
                    try commands.addComponent(entity, PhysicsPlugin.AngularVelocity, .{ .x = ang_x, .y = ang_y, .z = ang_z });
                },
                .torus => {
                    try commands.addComponent(entity, GraphicsPlugin.Torus3D, .{ .radius = 0.5, .ring_radius = 0.15, .sides = 24, .rings = 24 });
                    try commands.addComponent(entity, Rotation, .{});
                    try commands.addComponent(entity, PhysicsPlugin.AngularVelocity, .{ .x = ang_x, .y = ang_y, .z = ang_z });
                },
            }
            game.spawn_count += 1;
        }

        // F5 - Save
        if (keyboard.isPressed(.F5)) {
            try SerializationPlugin.saveGame(commands, save_file);
            std.debug.print("Game saved!\n", .{});
        }

        // F9 - Load
        if (keyboard.isPressed(.F9)) {
            try SerializationPlugin.loadGame(commands, save_file);
            std.debug.print("Game loaded!\n", .{});
            return; // Skip remaining input handling to avoid stale resource pointers
        }

        // R - Reset camera
        if (keyboard.isPressed(.R)) {
            // Reset fly mode
            game.yaw = std.math.pi;
            game.pitch = -0.3;
            // Reset orbit mode
            game.orbit_angle = 0;
            game.orbit_pitch = 0.3;
            game.orbit_distance = 15;
            // Reset time
            time.time_scale = 1.0;
            game.paused = false;
        }
    }

    // Convert hue (0-1) to RGB color
    fn hueToRgb(hue: f32) Color {
        const h = hue * 6.0;
        const i = @floor(h);
        const f = h - i;
        const q = 1.0 - f;

        const idx = @as(u32, @intFromFloat(i)) % 6;
        return switch (idx) {
            0 => Color{ .r = 1.0, .g = f, .b = 0.0, .a = 1.0 },
            1 => Color{ .r = q, .g = 1.0, .b = 0.0, .a = 1.0 },
            2 => Color{ .r = 0.0, .g = 1.0, .b = f, .a = 1.0 },
            3 => Color{ .r = 0.0, .g = q, .b = 1.0, .a = 1.0 },
            4 => Color{ .r = f, .g = 0.0, .b = 1.0, .a = 1.0 },
            else => Color{ .r = 1.0, .g = 0.0, .b = q, .a = 1.0 },
        };
    }

    fn updateAllMaterials(materials: Query(struct { GraphicsPlugin.Material }), shader: GraphicsPlugin.ShaderType) void {
        for (materials.entities) |entity| {
            if (!materials.filter(entity)) continue;
            const mat = materials.getComponentMut(entity, GraphicsPlugin.Material);
            mat.shader = shader;
        }
    }

    fn updateAnimationTime(
        time: Resource(TimePlugin.Time),
        game: ResourceMut(GameState),
    ) void {
        // Accumulate scaled time for animations (respects time_scale/pause)
        game.animation_time += time.delta_time * time.time_scale;
    }

    fn updateOrbiting(
        game: Resource(GameState),
        orbiting: Query(struct { Orbiting, Transform }),
    ) void {
        const t = game.animation_time;

        for (orbiting.entities) |entity| {
            if (!orbiting.filter(entity)) continue;
            const orbit = orbiting.getComponent(entity, Orbiting);
            const transform = orbiting.getComponentMut(entity, Transform);

            const angle = t * orbit.speed;
            transform.x = orbit.center_x + orbit.radius * @cos(angle);
            transform.z = orbit.center_z + orbit.radius * @sin(angle);
        }
    }

    fn updateBouncing(
        game: Resource(GameState),
        bouncing: Query(struct { Bouncing, Transform }),
    ) void {
        const t = game.animation_time;

        for (bouncing.entities) |entity| {
            if (!bouncing.filter(entity)) continue;
            const bounce = bouncing.getComponent(entity, Bouncing);
            const transform = bouncing.getComponentMut(entity, Transform);

            const range = bounce.max_y - bounce.min_y;
            const phase = (@sin(t * 2.0) + 1.0) / 2.0; // 0 to 1
            transform.y = bounce.min_y + range * phase;
        }
    }

    fn updatePulsing(
        game: Resource(GameState),
        pulsing: Query(struct { Pulsing, Scale }),
    ) void {
        const t = game.animation_time;

        for (pulsing.entities) |entity| {
            if (!pulsing.filter(entity)) continue;
            const pulse = pulsing.getComponent(entity, Pulsing);
            const scale = pulsing.getComponentMut(entity, Scale);

            const range = pulse.max_scale - pulse.min_scale;
            const phase = (@sin(t * pulse.speed) + 1.0) / 2.0;
            const s = pulse.min_scale + range * phase;
            scale.x = s;
            scale.y = s;
            scale.z = s;
        }
    }

    fn updateCamera(
        keyboard: Resource(InputPlugin.Keyboard),
        mouse: Resource(InputPlugin.Mouse),
        time: Resource(TimePlugin.Time),
        game: ResourceMut(GameState),
        camera: ResourceMut(GraphicsPlugin.Camera3D),
    ) void {
        const dt = time.delta_time;

        switch (game.camera_mode) {
            .orbit => {
                // Mouse for orbit control (when captured)
                if (game.mouse_captured) {
                    const mouse_sensitivity: f32 = 0.005;
                    game.orbit_angle += mouse.dx * mouse_sensitivity;
                    game.orbit_pitch = std.math.clamp(
                        game.orbit_pitch - mouse.dy * mouse_sensitivity,
                        -1.4,
                        1.4,
                    );
                }

                // Arrow keys control orbit (alternative to mouse)
                const orbit_speed: f32 = 1.5;
                if (keyboard.isHeld(.LEFT)) game.orbit_angle -= orbit_speed * dt;
                if (keyboard.isHeld(.RIGHT)) game.orbit_angle += orbit_speed * dt;
                if (keyboard.isHeld(.UP)) game.orbit_pitch = @min(1.4, game.orbit_pitch + orbit_speed * dt);
                if (keyboard.isHeld(.DOWN)) game.orbit_pitch = @max(-1.4, game.orbit_pitch - orbit_speed * dt);

                // Mouse wheel for zoom
                if (mouse.scroll_y != 0) {
                    game.orbit_distance = std.math.clamp(
                        game.orbit_distance - mouse.scroll_y * 0.5,
                        5,
                        50,
                    );
                }

                // Q/E control distance (alternative to mouse wheel)
                if (keyboard.isHeld(.Q)) game.orbit_distance = @max(5, game.orbit_distance - 10 * dt);
                if (keyboard.isHeld(.E)) game.orbit_distance = @min(50, game.orbit_distance + 10 * dt);

                // WASD movement for orbit center (camera-relative on XZ plane)
                const move_speed: f32 = 5.0;
                const forward_x = -@sin(game.orbit_angle);
                const forward_z = -@cos(game.orbit_angle);
                const right_x = @cos(game.orbit_angle);
                const right_z = -@sin(game.orbit_angle);

                if (keyboard.isHeld(.W)) {
                    camera.target[0] += forward_x * move_speed * dt;
                    camera.target[2] += forward_z * move_speed * dt;
                }
                if (keyboard.isHeld(.S)) {
                    camera.target[0] -= forward_x * move_speed * dt;
                    camera.target[2] -= forward_z * move_speed * dt;
                }
                if (keyboard.isHeld(.A)) {
                    camera.target[0] -= right_x * move_speed * dt;
                    camera.target[2] -= right_z * move_speed * dt;
                }
                if (keyboard.isHeld(.D)) {
                    camera.target[0] += right_x * move_speed * dt;
                    camera.target[2] += right_z * move_speed * dt;
                }

                // Calculate orbit position around target
                const x = camera.target[0] + game.orbit_distance * @cos(game.orbit_pitch) * @sin(game.orbit_angle);
                const y = camera.target[1] + game.orbit_distance * @sin(game.orbit_pitch);
                const z = camera.target[2] + game.orbit_distance * @cos(game.orbit_pitch) * @cos(game.orbit_angle);

                camera.eye = .{ x, y, z };
            },
            .fly => {
                // ===== MOUSE LOOK =====
                // Directly update yaw/pitch from mouse delta (simple and consistent)
                if (game.mouse_captured) {
                    const mouse_sensitivity: f32 = 0.003;
                    game.yaw -= mouse.dx * mouse_sensitivity;
                    game.pitch = std.math.clamp(
                        game.pitch - mouse.dy * mouse_sensitivity,
                        -1.5, // ~86 degrees down
                        1.5, // ~86 degrees up
                    );
                }

                // Arrow keys for look (alternative to mouse)
                const look_speed: f32 = 2.0;
                if (keyboard.isHeld(.LEFT)) game.yaw += look_speed * dt;
                if (keyboard.isHeld(.RIGHT)) game.yaw -= look_speed * dt;
                if (keyboard.isHeld(.UP)) game.pitch = @min(1.5, game.pitch + look_speed * dt);
                if (keyboard.isHeld(.DOWN)) game.pitch = @max(-1.5, game.pitch - look_speed * dt);

                // ===== CALCULATE CAMERA VECTORS FROM YAW/PITCH =====
                // Forward direction from yaw/pitch
                const cos_pitch = @cos(game.pitch);
                const forward_x = @sin(game.yaw) * cos_pitch;
                const forward_y = @sin(game.pitch);
                const forward_z = @cos(game.yaw) * cos_pitch;

                // Right vector (perpendicular to forward on XZ plane)
                const right_x = @cos(game.yaw);
                const right_z = -@sin(game.yaw);

                // ===== WASD MOVEMENT =====
                // Move relative to camera direction (XZ plane for ground movement)
                const move_speed: f32 = 10.0;
                var move_x: f32 = 0;
                var move_y: f32 = 0;
                var move_z: f32 = 0;

                // Forward/back (W/S) - move in camera's look direction on XZ plane
                const ground_forward_x = @sin(game.yaw);
                const ground_forward_z = @cos(game.yaw);

                if (keyboard.isHeld(.W)) {
                    move_x += ground_forward_x * move_speed * dt;
                    move_z += ground_forward_z * move_speed * dt;
                }
                if (keyboard.isHeld(.S)) {
                    move_x -= ground_forward_x * move_speed * dt;
                    move_z -= ground_forward_z * move_speed * dt;
                }
                if (keyboard.isHeld(.A)) {
                    move_x += right_x * move_speed * dt;
                    move_z += right_z * move_speed * dt;
                }
                if (keyboard.isHeld(.D)) {
                    move_x -= right_x * move_speed * dt;
                    move_z -= right_z * move_speed * dt;
                }
                if (keyboard.isHeld(.Q)) move_y -= move_speed * dt;
                if (keyboard.isHeld(.E)) move_y += move_speed * dt;

                // Apply movement to camera position
                camera.eye[0] += move_x;
                camera.eye[1] += move_y;
                camera.eye[2] += move_z;

                // ===== UPDATE TARGET FROM EYE + FORWARD =====
                // Target is always 10 units in front of eye
                camera.target = .{
                    camera.eye[0] + forward_x * 10,
                    camera.eye[1] + forward_y * 10,
                    camera.eye[2] + forward_z * 10,
                };
            },
        }
    }

    fn monitorErrors(
        game_errors: EventReader(BuiltinPlugin.GameLoopError),
        event_errors: EventReader(BuiltinPlugin.EventLoopError),
    ) void {
        // Log any errors that occurred
        for (game_errors.read()) |err| {
            std.debug.print("GameLoopError: {any}\n", .{err.err});
        }
        for (event_errors.read()) |err| {
            std.debug.print("EventLoopError: {any}\n", .{err.err});
        }
    }

    fn drawHelpWindow(game: Resource(GameState)) void {
        if (!game.show_help) return;

        ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 350, .y = 580 }, .FirstUseEver);

        if (ImGuiPlugin.begin("Help (F1 to toggle)", null, .None)) {
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "ZENITHOR 3D SHOWCASE");
            ImGuiPlugin.separator();
            ImGuiPlugin.textWrapped("This example demonstrates all major features of the Zenithor game engine.");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Camera Controls");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("Space: Toggle orbit/fly mode");
            ImGuiPlugin.bulletText("Tab: Toggle mouse capture");
            ImGuiPlugin.bulletText("Mouse: Look around (1st person)");
            ImGuiPlugin.bulletText("Mouse Wheel: Zoom (orbit)");
            ImGuiPlugin.bulletText("WASD: Move camera");
            ImGuiPlugin.bulletText("Q/E: Up/down (fly), Zoom (orbit)");
            ImGuiPlugin.bulletText("Arrows: Look/orbit (alt)");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Shape Spawning");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("Left Click: Spawn shape");
            ImGuiPlugin.bulletText("4: Select Box");
            ImGuiPlugin.bulletText("5: Select Sphere");
            ImGuiPlugin.bulletText("6: Select Cylinder");
            ImGuiPlugin.bulletText("7: Select Torus");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Visual Controls");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("1: Unlit shader");
            ImGuiPlugin.bulletText("2: Blinn-Phong shader");
            ImGuiPlugin.bulletText("3: PBR shader");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Time Controls");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("P: Toggle pause");
            ImGuiPlugin.bulletText("+/-: Adjust time scale");
            ImGuiPlugin.bulletText("R: Reset camera");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Save/Load");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("F5: Save game");
            ImGuiPlugin.bulletText("F9: Load game");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "Press F1 to hide this window");
        }
        ImGuiPlugin.end();
    }

    fn drawStatsWindow(
        game: Resource(GameState),
        time: Resource(TimePlugin.Time),
        camera: Resource(GraphicsPlugin.Camera3D),
    ) void {
        if (!game.show_stats) return;

        ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 500 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 280, .y = 250 }, .FirstUseEver);

        if (ImGuiPlugin.begin("Statistics", null, .None)) {
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Performance");
            ImGuiPlugin.separator();
            ImGuiPlugin.textFmt("FPS: {d:.1}", .{time.fps});
            ImGuiPlugin.textFmt("Frame Time: {d:.2}ms", .{time.delta_time * 1000.0});
            ImGuiPlugin.textFmt("Total Time: {d:.1}s", .{time.total_time});
            ImGuiPlugin.textFmt("Frame: {}", .{time.frame_count});

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Camera");
            ImGuiPlugin.separator();
            const mode_str: [:0]const u8 = switch (game.camera_mode) {
                .orbit => "Orbit",
                .fly => "Fly",
            };
            ImGuiPlugin.textFmt("Mode: {s}", .{mode_str});
            ImGuiPlugin.textFmt("Eye: ({d:.1}, {d:.1}, {d:.1})", .{
                camera.eye[0],
                camera.eye[1],
                camera.eye[2],
            });

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Shape Spawner");
            ImGuiPlugin.separator();
            const shape_str: [:0]const u8 = switch (game.selected_shape) {
                .box => "Box",
                .sphere => "Sphere",
                .cylinder => "Cylinder",
                .torus => "Torus",
            };
            ImGuiPlugin.textFmt("Selected: {s} (4-7)", .{shape_str});
            ImGuiPlugin.textFmt("Spawned: {}", .{game.spawn_count});
        }
        ImGuiPlugin.end();
    }

    fn drawControlsWindow(
        game: ResourceMut(GameState),
        time: ResourceMut(TimePlugin.Time),
        light: ResourceMut(GraphicsPlugin.Light3D),
        camera: ResourceMut(GraphicsPlugin.Camera3D),
        physics: ResourceMut(PhysicsPlugin.PhysicsConfig),
        materials: Query(struct { GraphicsPlugin.Material }),
    ) void {
        if (!game.show_controls) return;

        ImGuiPlugin.setNextWindowPos(.{ .x = 1000, .y = 10 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 270, .y = 550 }, .FirstUseEver);

        if (ImGuiPlugin.begin("Controls", null, .None)) {
            // Time controls
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Time");
            ImGuiPlugin.separator();
            _ = ig.igCheckbox("Paused", &game.paused);
            if (game.paused) {
                time.time_scale = 0.0;
            } else if (time.time_scale == 0.0) {
                time.time_scale = 1.0;
            }
            _ = ImGuiPlugin.sliderFloat("Time Scale", &time.time_scale, 0.0, 3.0);

            ImGuiPlugin.spacing();

            // Shader controls
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Shaders");
            ImGuiPlugin.separator();

            var shader_idx: i32 = switch (game.selected_shader) {
                .unlit => 0,
                .blinn_phong => 1,
                .pbr => 2,
            };
            const old_shader = shader_idx;
            _ = ig.igRadioButtonIntPtr("Unlit", &shader_idx, 0);
            _ = ig.igRadioButtonIntPtr("Blinn-Phong", &shader_idx, 1);
            _ = ig.igRadioButtonIntPtr("PBR", &shader_idx, 2);

            if (shader_idx != old_shader) {
                const new_shader: GraphicsPlugin.ShaderType = switch (shader_idx) {
                    0 => .unlit,
                    1 => .blinn_phong,
                    2 => .pbr,
                    else => .blinn_phong,
                };
                game.selected_shader = new_shader;
                updateAllMaterials(materials, new_shader);
            }

            ImGuiPlugin.spacing();

            // Light controls
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Lighting");
            ImGuiPlugin.separator();
            _ = ImGuiPlugin.sliderFloat("Light X", &light.position[0], -20.0, 20.0);
            _ = ImGuiPlugin.sliderFloat("Light Y", &light.position[1], 0.0, 30.0);
            _ = ImGuiPlugin.sliderFloat("Light Z", &light.position[2], -20.0, 20.0);
            _ = ImGuiPlugin.sliderFloat("Ambient", &light.ambient_strength, 0.0, 0.5);

            ImGuiPlugin.spacing();

            // Camera controls
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Camera");
            ImGuiPlugin.separator();
            _ = ImGuiPlugin.sliderFloat("FOV", &camera.fov, 30.0, 120.0);
            if (game.camera_mode == .orbit) {
                _ = ImGuiPlugin.sliderFloat("Distance", &game.orbit_distance, 5.0, 50.0);
            }

            ImGuiPlugin.spacing();

            // Physics controls
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Physics");
            ImGuiPlugin.separator();
            _ = ig.igCheckbox("Enabled", &physics.enabled);
            _ = ImGuiPlugin.sliderFloat("Damping", &physics.damping, 0.9, 1.0);

            ImGuiPlugin.spacing();

            // Window toggles
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Windows");
            ImGuiPlugin.separator();
            _ = ig.igCheckbox("Show Help", &game.show_help);
            _ = ig.igCheckbox("Show Stats", &game.show_stats);
            _ = ig.igCheckbox("Show Scene", &game.show_scene);
        }
        ImGuiPlugin.end();
    }

    fn drawSceneWindow(
        game: Resource(GameState),
        pass_action: ResourceMut(RenderContext.PassAction),
    ) void {
        if (!game.show_scene) return;

        ImGuiPlugin.setNextWindowPos(.{ .x = 1000, .y = 570 }, .FirstUseEver);
        ImGuiPlugin.setNextWindowSize(.{ .x = 270, .y = 200 }, .FirstUseEver);

        if (ImGuiPlugin.begin("Scene", null, .None)) {
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Background");
            ImGuiPlugin.separator();

            var bg_color: [3]f32 = .{
                pass_action.colors[0].clear_value.r,
                pass_action.colors[0].clear_value.g,
                pass_action.colors[0].clear_value.b,
            };
            if (ig.igColorEdit3("Color", &bg_color, 0)) {
                pass_action.colors[0].clear_value.r = bg_color[0];
                pass_action.colors[0].clear_value.g = bg_color[1];
                pass_action.colors[0].clear_value.b = bg_color[2];
            }

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Scene Objects");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("1 Ground plane");
            ImGuiPlugin.bulletText("1 Central sphere (gold)");
            ImGuiPlugin.bulletText("3 Orbiting objects");
            ImGuiPlugin.bulletText("2 Bouncing objects");
            ImGuiPlugin.bulletText("2 Pulsing objects");
            ImGuiPlugin.bulletText("4 Corner pillars + caps");
            ImGuiPlugin.bulletText("1 Arch torus");
        }
        ImGuiPlugin.end();
    }
};
