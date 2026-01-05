/// Example: Asset Loading
///
/// Demonstrates the asset management system:
/// - Loading textures (uses procedural texture when file not found)
/// - Monitoring asset loading states (unloaded/loading/ready/failed)
/// - Asset caching and refcounting
/// - Debug UI showing asset statistics
///
/// Note: This example requests "demo_texture.png" which may not exist.
/// The asset system gracefully handles missing files and shows the failed state.
///
/// See: plugins/asset/src/root.zig
const zenithor = @import("zenithor");
const AssetPlugin = @import("asset_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const RenderContext = @import("render_context_plugin");
const TimePlugin = @import("time_plugin");

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
                .system = showAssetUI,
                .stage = .render,
                .config = .{
                    .priority = 100, // After main rendering
                },
            },
        },
    };
};

/// Component to track which asset an entity is waiting for
const TestAssetComponent = struct {
    handle: AssetPlugin.TypedHandle(AssetPlugin.Texture),
    requested: bool = false,
};

fn setup(commands: anytype, pass_action: zenithor.ResourceMut(RenderContext.PassAction)) !void {
    pass_action.colors[0].clear_value = .{ .r = 0.15, .g = 0.15, .b = 0.2, .a = 1.0 };

    // Create an entity that will request an asset
    // Note: The handle will be initialized in requestAsset system
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
            // Request the asset (this will trigger loading)
            // Note: demo_texture.png may not exist - this demonstrates error handling
            comp.handle = try registry.createHandle(
                AssetPlugin.Texture,
                "demo_texture.png",
            );

            try writer.enqueue(.{
                .type_id = comp.handle.handle.id.type_id,
                .path = "demo_texture.png",
                .priority = 255,
                .requester = @bitCast(entity),
            });

            comp.requested = true;
            std.debug.print("[Game] Requested asset: demo_texture.png\n", .{});
        }
    }

    _ = commands;
}

fn showAssetUI(
    registry: zenithor.Resource(AssetPlugin.AssetRegistry),
    stats: zenithor.Resource(AssetPlugin.AssetStats),
    pipeline: zenithor.Resource(AssetPlugin.JobPipeline),
    query: zenithor.Query(struct { TestAssetComponent }),
) !void {
    if (ImGuiPlugin.begin("Asset Loading Demo", null, .None)) {
        ImGuiPlugin.text("Asset Management System");
        ImGuiPlugin.separator();

        // Show asset statistics
        ImGuiPlugin.text("Statistics:");
        ImGuiPlugin.textFmt("  Total Assets: {d}", .{stats.total_assets});
        ImGuiPlugin.textFmt("  Ready: {d}", .{stats.ready_assets});
        ImGuiPlugin.textFmt("  Loading: {d}", .{stats.loading_assets});
        ImGuiPlugin.textFmt("  Failed: {d}", .{stats.failed_assets});

        const cpu_mb = @as(f32, @floatFromInt(registry.total_cpu_bytes)) / (1024.0 * 1024.0);
        const gpu_mb = @as(f32, @floatFromInt(registry.total_gpu_bytes)) / (1024.0 * 1024.0);
        ImGuiPlugin.textFmt("  CPU Memory: {d:.2} MB", .{cpu_mb});
        ImGuiPlugin.textFmt("  GPU Memory: {d:.2} MB", .{gpu_mb});

        ImGuiPlugin.separator();

        // Show job queue status
        ImGuiPlugin.text("Job Pipeline:");
        ImGuiPlugin.textFmt("  IO Queue: {d}", .{pipeline.io_queue.items.len});
        ImGuiPlugin.textFmt("  Decode Queue: {d}", .{pipeline.decode_queue.items.len});
        ImGuiPlugin.textFmt("  Upload Queue: {d}", .{pipeline.upload_queue.items.len});

        ImGuiPlugin.separator();

        // Show test asset status
        ImGuiPlugin.text("Test Asset (demo_texture.png):");
        for (query.entities) |_| {
            const comp = query.getComponent(query.entities[0], TestAssetComponent);

            if (registry.validateHandle(comp.handle.handle)) |entry| {
                ImGuiPlugin.textFmt("  State: {s}", .{@tagName(entry.state)});
                ImGuiPlugin.textFmt("  Generation: {d}", .{entry.generation});
                ImGuiPlugin.textFmt("  Refcount: {d}", .{entry.refcount});

                if (entry.last_error) |err| {
                    ImGuiPlugin.textFmt("  Error: {s}", .{err.message});
                }

                if (entry.state == .ready) {
                    ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.2, .w = 1.0 }, "  Asset loaded successfully!");
                }
            } else {
                ImGuiPlugin.text("  Status: Invalid handle");
            }
            break; // Only show first entity
        }

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Note: demo_texture.png is intentionally missing to");
        ImGuiPlugin.text("demonstrate asset error handling.");
    }
    ImGuiPlugin.end();
}

const std = @import("std");
