/// Example: Sprite Rendering
///
/// Demonstrates ECS-integrated sprite rendering using SpritePlugin:
/// - Loading textures via AssetPlugin with embedded assets
/// - Automatic texture handle resolution and caching
/// - Sprite rendering with Transform, Scale, and Color
/// - Z-depth ordering with other 2D elements
///
/// The demo_texture.png is an 8x8 checkerboard pattern stored in examples/assets/.
/// SpritePlugin handles all sokol.gl rendering automatically.
///
/// See: plugins/sprite/CLAUDE.md
const std = @import("std");
const log = std.log.scoped(.sprite_rendering);
const zenithor = @import("zenithor");
const AssetPlugin = @import("asset_plugin");
const SpritePlugin = @import("sprite_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const Renderer = @import("renderer_plugin");

const Transform = zenithor.Transform;
const Scale = zenithor.Scale;
const Color = zenithor.Color;

/// Embed the demo texture at compile time
const demo_texture_png = @embedFile("assets/demo_texture.png");

pub fn main() !void {
    // SpritePlugin works standalone - RendererPlugin handles sokol.gl.draw()
    zenithor.run(.{Game}, .{});
}

const Game = struct {
    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const Requires = .{ AssetPlugin, SpritePlugin, ImGuiPlugin };

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{
                .system = showUI,
                .stage = .render,
                .config = .{ .priority = 199 }, // After sprite rendering (115), before flushGL (200)
            },
        },
    };
};

fn setup(
    commands: anytype,
    allocator: std.mem.Allocator,
    pass_action: zenithor.ResourceMut(Renderer.PassAction),
    embedded: zenithor.ResourceMut(AssetPlugin.EmbeddedAssets),
    registry: zenithor.ResourceMut(AssetPlugin.AssetRegistry),
    writer: zenithor.EventWriter(AssetPlugin.AssetRequest),
) !void {
    // Set background color
    pass_action.colors[0].clear_value = .{ .r = 0.15, .g = 0.15, .b = 0.2, .a = 1.0 };

    // Register embedded texture (works on all platforms)
    try embedded.register(allocator, "demo_texture.png", demo_texture_png);

    // Create asset handle and request load
    const locator = AssetPlugin.AssetLocator.embedded("demo_texture.png");
    const handle = try registry.createHandle(AssetPlugin.Texture, locator);

    // Request the asset load
    try writer.enqueue(.{
        .type_id = handle.handle.id.type_id,
        .path = locator.path,
        .source = locator.source,
        .priority = 255,
        .requester = 0,
    });

    // Create sprite entity - SpritePlugin handles rendering automatically!
    // Center on screen with anchor at center
    const screen_w = zenithor.windowWidthF();
    const screen_h = zenithor.windowHeightF();

    // Use createEntity + addComponent for runtime values (screen dimensions)
    const entity = commands.createEntity();
    try commands.addComponent(entity, Transform, .{
        .x = screen_w / 2.0,
        .y = screen_h / 2.0 - 50, // Offset up for UI
    });
    try commands.addComponent(entity, SpritePlugin.Sprite, .{
        .anchor_x = 0.5, // Center anchor
        .anchor_y = 0.5,
    });
    try commands.addComponent(entity, SpritePlugin.TextureRef, .{ .handle = handle });
    try commands.addComponent(entity, Scale, .{ .x = 32.0, .y = 32.0 }); // 8x8 texture scaled to 256x256
    try commands.addComponent(entity, Color, Color.white);

    log.info("Created sprite entity with asset handle", .{});
}

fn showUI(
    registry: zenithor.Resource(AssetPlugin.AssetRegistry),
    stats: zenithor.Resource(AssetPlugin.AssetStats),
    sprites: zenithor.Query(struct { SpritePlugin.Sprite, SpritePlugin.TextureRef }),
) !void {
    // Position the window at the bottom
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = zenithor.windowHeightF() - 200 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 320, .y = 190 }, .Once);

    if (ImGuiPlugin.begin("Sprite Rendering Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "SpritePlugin Demo");
        ImGuiPlugin.separator();

        // Show asset statistics
        ImGuiPlugin.text("Asset Stats:");
        ImGuiPlugin.textFmt("  Total: {d}  Ready: {d}  Loading: {d}", .{
            stats.total_assets,
            stats.ready_assets,
            stats.loading_assets,
        });

        const cpu_kb = @as(f32, @floatFromInt(registry.total_cpu_bytes)) / 1024.0;
        const gpu_kb = @as(f32, @floatFromInt(registry.total_gpu_bytes)) / 1024.0;
        ImGuiPlugin.textFmt("  Memory: {d:.1} KB CPU, {d:.1} KB GPU", .{ cpu_kb, gpu_kb });

        ImGuiPlugin.separator();

        // Show sprite entity info
        ImGuiPlugin.text("Sprite Entity:");
        for (sprites.entities) |entity| {
            const ref = sprites.getComponent(entity, SpritePlugin.TextureRef);

            if (ref.resolved) {
                ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.2, .w = 1.0 }, "  Status: Rendering");
                ImGuiPlugin.textFmt("  Texture: {d}x{d} px", .{ ref.natural_width, ref.natural_height });
                ImGuiPlugin.textFmt("  Display: {d}x{d} px (32x scale)", .{
                    ref.natural_width * 32,
                    ref.natural_height * 32,
                });
            } else {
                ImGuiPlugin.textColored(.{ .x = 1.0, .y = 1.0, .z = 0.2, .w = 1.0 }, "  Status: Loading...");
            }
            break;
        }

        ImGuiPlugin.separator();
        ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "No manual sokol.gl calls needed!");
    }
    ImGuiPlugin.end();
}
