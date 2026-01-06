/// Example: Asset Loading
///
/// Demonstrates the asset management system with actual texture rendering:
/// - Loading textures using explicit source (embedded or filesystem)
/// - PNG decoding and GPU texture upload
/// - Rendering the loaded texture as a 2D sprite using sokol.gl
/// - Asset state monitoring (queued/io/decode/upload/ready/failed)
///
/// The demo_texture.png is an 8x8 checkerboard pattern stored in examples/assets/.
/// Once loaded, it's displayed as a scaled sprite in the center of the screen.
///
/// This example uses embedded assets via @embedFile, which works on both
/// native and WASM builds. Users explicitly specify the source per-asset.
///
/// See: plugins/asset/src/root.zig
const std = @import("std");
const zenithor = @import("zenithor");
const sokol = @import("sokol");
const AssetPlugin = @import("asset_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const RenderContext = @import("render_context_plugin");
const TimePlugin = @import("time_plugin");

/// Embed the demo texture at compile time
const demo_texture_png = @embedFile("assets/demo_texture.png");

pub fn main() !void {
    zenithor.run(.{ TimePlugin, AssetPlugin, ImGuiPlugin, Game }, .{});
}

const Game = struct {
    pub const Components = .{TestAssetComponent};
    pub const Resources = .{};
    pub const Events = .{};

    pub const Requires = .{ AssetPlugin, ImGuiPlugin };

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = requestAsset, .stage = .update },
            .{
                .system = renderSprite,
                .stage = .render,
                .config = .{ .priority = 50 }, // Before ImGui
            },
            .{
                .system = showAssetUI,
                .stage = .render,
                .config = .{ .priority = 100 }, // After sprite rendering
            },
        },
    };
};

/// Component to track which asset an entity is waiting for
const TestAssetComponent = struct {
    handle: AssetPlugin.TypedHandle(AssetPlugin.Texture),
    requested: bool = false,
};

fn setup(
    commands: anytype,
    allocator: std.mem.Allocator,
    pass_action: zenithor.ResourceMut(RenderContext.PassAction),
    embedded: zenithor.ResourceMut(AssetPlugin.EmbeddedAssets),
) !void {
    pass_action.colors[0].clear_value = .{ .r = 0.15, .g = 0.15, .b = 0.2, .a = 1.0 };

    // Register embedded texture (works on all platforms)
    try embedded.register(allocator, "demo_texture.png", demo_texture_png);

    // Create an entity that will request an asset
    _ = try commands.createEntityWith(.{
        TestAssetComponent{
            .handle = .{ .handle = .{
                .id = .{ .type_id = 0, .path_hash = 0 },
                .generation = 0,
            } },
            .requested = false,
        },
    });
}

fn requestAsset(
    commands: anytype,
    registry: zenithor.ResourceMut(AssetPlugin.AssetRegistry),
    query: zenithor.Query(struct { TestAssetComponent }),
    writer: zenithor.EventWriter(AssetPlugin.AssetRequest),
) !void {
    for (query.entities) |entity| {
        const comp = query.getComponentMut(entity, TestAssetComponent);

        if (!comp.requested) {
            // Request the demo texture from embedded source (explicit per-asset choice)
            const locator = AssetPlugin.AssetLocator.embedded("demo_texture.png");
            comp.handle = try registry.createHandle(AssetPlugin.Texture, locator);

            try writer.enqueue(.{
                .type_id = comp.handle.handle.id.type_id,
                .path = locator.path,
                .source = locator.source,
                .priority = 255,
                .requester = @bitCast(entity),
            });

            comp.requested = true;
            std.debug.print("[Game] Requested asset: demo_texture.png (source: embedded)\n", .{});
        }
    }

    _ = commands;
}

/// Render the loaded texture as a sprite
fn renderSprite(
    registry: zenithor.Resource(AssetPlugin.AssetRegistry),
    query: zenithor.Query(struct { TestAssetComponent }),
) !void {
    // Find the loaded texture
    for (query.entities) |_| {
        const comp = query.getComponent(query.entities[0], TestAssetComponent);

        if (registry.validateHandle(comp.handle.handle)) |entry| {
            if (entry.state == .ready) {
                if (entry.payload) |payload| {
                    const texture: *const AssetPlugin.Texture = @ptrCast(@alignCast(payload));

                    // Draw the texture as a scaled sprite using sokol.gl
                    drawTexturedQuad(texture);
                }
            }
        }
        break;
    }
}

/// Draw a textured quad using sokol.gl immediate mode
fn drawTexturedQuad(texture: *const AssetPlugin.Texture) void {
    // Setup 2D orthographic projection
    sokol.gl.defaults();
    sokol.gl.matrixModeProjection();
    sokol.gl.ortho(0, sokol.app.widthf(), sokol.app.heightf(), 0, -1, 1);

    // Enable texturing and bind the texture (using cached view, not per-frame creation)
    sokol.gl.enableTexture();
    sokol.gl.texture(texture.view, texture.sampler);

    // Calculate sprite position and size
    // Scale up the 8x8 texture to be visible (32x scale = 256x256 display)
    const scale: f32 = 32.0;
    const sprite_w = @as(f32, @floatFromInt(texture.width)) * scale;
    const sprite_h = @as(f32, @floatFromInt(texture.height)) * scale;

    // Center the sprite on screen
    const screen_w = sokol.app.widthf();
    const screen_h = sokol.app.heightf();
    const x = (screen_w - sprite_w) / 2.0;
    const y = (screen_h - sprite_h) / 2.0 - 50.0; // Offset up a bit for UI

    // Draw textured quad
    sokol.gl.c4f(1.0, 1.0, 1.0, 1.0); // White tint (use texture colors)
    sokol.gl.beginQuads();

    // Top-left
    sokol.gl.t2f(0.0, 0.0);
    sokol.gl.v2f(x, y);

    // Top-right
    sokol.gl.t2f(1.0, 0.0);
    sokol.gl.v2f(x + sprite_w, y);

    // Bottom-right
    sokol.gl.t2f(1.0, 1.0);
    sokol.gl.v2f(x + sprite_w, y + sprite_h);

    // Bottom-left
    sokol.gl.t2f(0.0, 1.0);
    sokol.gl.v2f(x, y + sprite_h);

    sokol.gl.end();
    sokol.gl.disableTexture();

    // Flush sokol.gl commands
    sokol.gl.draw();
}

fn showAssetUI(
    registry: zenithor.Resource(AssetPlugin.AssetRegistry),
    stats: zenithor.Resource(AssetPlugin.AssetStats),
    pipeline: zenithor.Resource(AssetPlugin.JobPipeline),
    query: zenithor.Query(struct { TestAssetComponent }),
) !void {
    // Position the window at the bottom
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = sokol.app.heightf() - 260 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 320, .y = 250 }, .Once);

    if (ImGuiPlugin.begin("Asset Loading Demo", null, .None)) {
        ImGuiPlugin.text("Asset Management System");
        ImGuiPlugin.separator();

        // Show asset statistics
        ImGuiPlugin.text("Statistics:");
        ImGuiPlugin.textFmt("  Total Assets: {d}", .{stats.total_assets});
        ImGuiPlugin.textFmt("  Ready: {d}", .{stats.ready_assets});
        ImGuiPlugin.textFmt("  Loading: {d}", .{stats.loading_assets});
        ImGuiPlugin.textFmt("  Failed: {d}", .{stats.failed_assets});

        const cpu_kb = @as(f32, @floatFromInt(registry.total_cpu_bytes)) / 1024.0;
        const gpu_kb = @as(f32, @floatFromInt(registry.total_gpu_bytes)) / 1024.0;
        ImGuiPlugin.textFmt("  CPU Memory: {d:.2} KB", .{cpu_kb});
        ImGuiPlugin.textFmt("  GPU Memory: {d:.2} KB", .{gpu_kb});

        ImGuiPlugin.separator();

        // Show job queue status
        ImGuiPlugin.text("Job Pipeline:");
        ImGuiPlugin.textFmt("  IO Queue: {d}", .{pipeline.io_queue.items.len});
        ImGuiPlugin.textFmt("  Decode Queue: {d}", .{pipeline.decode_queue.items.len});
        ImGuiPlugin.textFmt("  Upload Queue: {d}", .{pipeline.upload_queue.items.len});

        ImGuiPlugin.separator();

        // Show test asset status
        ImGuiPlugin.text("Texture (demo_texture.png):");
        for (query.entities) |_| {
            const comp = query.getComponent(query.entities[0], TestAssetComponent);

            if (registry.validateHandle(comp.handle.handle)) |entry| {
                ImGuiPlugin.textFmt("  State: {s}", .{@tagName(entry.state)});

                if (entry.last_error) |err| {
                    ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.3, .z = 0.3, .w = 1.0 }, "  Error:");
                    ImGuiPlugin.textFmt("    {s}", .{err.message});
                }

                if (entry.state == .ready) {
                    ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.2, .w = 1.0 }, "  Loaded & Rendering!");

                    if (entry.payload) |payload| {
                        const texture: *const AssetPlugin.Texture = @ptrCast(@alignCast(payload));
                        ImGuiPlugin.textFmt("  Size: {d}x{d} pixels", .{ texture.width, texture.height });
                        ImGuiPlugin.textFmt("  GPU Image ID: {d}", .{texture.image.id});
                    }
                }
            } else {
                ImGuiPlugin.text("  Status: Waiting...");
            }
            break;
        }
    }
    ImGuiPlugin.end();
}
