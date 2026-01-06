/// Sprite Plugin
///
/// ECS-integrated 2D textured sprite rendering with automatic asset handle
/// resolution, sprite sheets, and Z-depth ordering.
///
/// See: plugins/sprite/CLAUDE.md
const std = @import("std");
const sparze = @import("sparze");
const sokol = @import("sokol");
const zenithor = @import("zenithor");
const AssetPlugin = @import("asset_plugin");
const RenderContextPlugin = @import("render_context_plugin");

const Query = sparze.Query;
const Resource = sparze.Resource;
const Transform = zenithor.Transform;
const Scale = zenithor.Scale;
const Color = zenithor.Color;

// =============================================================================
// Components
// =============================================================================

/// 2D textured sprite component
///
/// Controls how a texture is rendered: size, UV region, flipping, and anchor.
/// Requires a `TextureRef` component to specify which texture to use.
pub const Sprite = struct {
    /// Display size in pixels. If 0, uses the texture's natural size.
    width: f32 = 0,
    height: f32 = 0,

    /// UV coordinates (normalized 0-1) defining the texture region to display.
    /// Default shows the entire texture. Override for atlas regions.
    uv_min: [2]f32 = .{ 0, 0 },
    uv_max: [2]f32 = .{ 1, 1 },

    /// Horizontal flip (mirrors texture along Y axis)
    flip_x: bool = false,
    /// Vertical flip (mirrors texture along X axis)
    flip_y: bool = false,

    /// Anchor point (0-1 normalized) determining where Transform position
    /// is relative to the sprite's bounding box.
    /// Default: top-left (0, 0) - consistent with Rectangle and 2D coordinate system.
    /// Use (0.5, 0.5) for center anchor (useful for rotations/scaling around center).
    anchor_x: f32 = 0,
    anchor_y: f32 = 0,

    pub fn format(self: Sprite, writer: anytype) !void {
        try writer.print("Sprite(size: {d:.0}x{d:.0}, anchor: ({d:.2}, {d:.2}))", .{
            self.width,
            self.height,
            self.anchor_x,
            self.anchor_y,
        });
    }
};

/// Links a sprite to a texture asset with cached GPU handles.
///
/// Uses asset handle for safe reference with automatic hot-reload support.
/// The cache is updated lazily when the texture is first accessed or when
/// the asset generation changes (indicating a reload).
pub const TextureRef = struct {
    /// Asset handle for the texture
    handle: AssetPlugin.TypedHandle(AssetPlugin.Texture),

    // Cached GPU resources (managed by resolveTextureRefs system)
    cached_view: sokol.gfx.View = .{},
    cached_sampler: sokol.gfx.Sampler = .{},
    cached_generation: u32 = 0,

    // Cached texture dimensions
    natural_width: u32 = 0,
    natural_height: u32 = 0,

    /// True when cache is valid and texture is ready for rendering
    resolved: bool = false,

    pub fn format(self: TextureRef, writer: anytype) !void {
        try writer.print("TextureRef(resolved: {}, size: {d}x{d})", .{
            self.resolved,
            self.natural_width,
            self.natural_height,
        });
    }
};

/// Sprite sheet metadata for atlas-based sprites.
///
/// Defines a uniform grid of cells within a texture atlas.
/// Use with `SpriteIndex` to select which cell to display.
pub const SpriteSheet = struct {
    /// Width of each cell in pixels
    cell_width: u32,
    /// Height of each cell in pixels
    cell_height: u32,
    /// Number of columns in the grid
    columns: u32,
    /// Number of rows in the grid
    rows: u32,
    /// Padding between cells in pixels (optional)
    padding: u32 = 0,
    /// Margin around the entire sheet in pixels (optional)
    margin: u32 = 0,

    pub fn format(self: SpriteSheet, writer: anytype) !void {
        try writer.print("SpriteSheet(cell: {d}x{d}, grid: {d}x{d})", .{
            self.cell_width,
            self.cell_height,
            self.columns,
            self.rows,
        });
    }
};

/// Current cell index within a sprite sheet.
///
/// Linear index starting at 0 (top-left), incrementing left-to-right, top-to-bottom.
pub const SpriteIndex = struct {
    /// Linear index into the sprite sheet (0 = first cell)
    index: u32 = 0,

    pub fn format(self: SpriteIndex, writer: anytype) !void {
        try writer.print("SpriteIndex({d})", .{self.index});
    }
};

// =============================================================================
// Systems
// =============================================================================

/// Resolves texture asset handles to cached GPU resources.
///
/// Runs in pre_render stage to ensure textures are ready before drawing.
/// Only updates cache when:
/// - First access (resolved == false)
/// - Asset generation changed (hot-reload detected via entry generation)
fn resolveTextureRefs(
    registry: Resource(AssetPlugin.AssetRegistry),
    query: Query(struct { TextureRef }),
) void {
    for (query.entities) |entity| {
        const ref = query.getComponentMut(entity, TextureRef);

        // Look up entry by ID (not validateHandle) to support hot-reload.
        // When asset reloads, entry.generation increments but handle.generation stays old.
        // Using getEntryConst lets us detect the reload and re-resolve.
        const entry = registry.getEntryConst(ref.handle.handle.id) orelse {
            ref.resolved = false;
            continue;
        };

        // Check if cache is still valid (using entry generation, not handle generation)
        if (ref.resolved and ref.cached_generation == entry.generation) {
            continue; // Cache is still valid
        }

        // Check if asset is ready
        if (entry.state != .ready) {
            ref.resolved = false;
            continue;
        }

        // Get texture payload
        const payload = entry.payload orelse {
            ref.resolved = false;
            continue;
        };

        const texture: *const AssetPlugin.Texture = @ptrCast(@alignCast(payload));

        // Update cache with entry's current generation
        ref.cached_view = texture.view;
        ref.cached_sampler = texture.sampler;
        ref.cached_generation = entry.generation;
        ref.natural_width = texture.width;
        ref.natural_height = texture.height;
        ref.resolved = true;
    }
}

/// Renders all sprite entities as textured quads.
///
/// Respects Transform.z for depth ordering with other 2D shapes.
/// Supports optional Color tint, Scale, SpriteSheet, and SpriteIndex.
fn drawSprites(
    query: Query(struct { Sprite, TextureRef, Transform, ?Color, ?SpriteSheet, ?SpriteIndex, ?Scale }),
) void {
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;

        const ref = query.getComponent(entity, TextureRef);
        if (!ref.resolved) continue; // Texture not ready

        const sprite = query.getComponent(entity, Sprite);
        const transform = query.getComponent(entity, Transform);
        const color = query.getOptional(entity, Color) orelse Color.white;
        const scale = query.getOptional(entity, Scale);

        // Calculate UV coordinates
        var uv_min = sprite.uv_min;
        var uv_max = sprite.uv_max;

        // Override UVs if sprite sheet is present
        if (query.getOptional(entity, SpriteSheet)) |sheet| {
            // Guard against invalid sprite sheet configuration
            if (sheet.columns == 0 or sheet.rows == 0 or ref.natural_width == 0 or ref.natural_height == 0) {
                continue; // Skip rendering - invalid configuration
            }

            const max_cells = sheet.columns * sheet.rows;
            const idx = if (query.getOptional(entity, SpriteIndex)) |si|
                // Clamp index to valid range to prevent UV overflow
                @min(si.index, if (max_cells > 0) max_cells - 1 else 0)
            else
                0;

            // Calculate cell position in grid
            const col = idx % sheet.columns;
            const row = idx / sheet.columns;

            // Calculate UV size per cell (accounting for margin/padding)
            const tex_w: f32 = @floatFromInt(ref.natural_width);
            const tex_h: f32 = @floatFromInt(ref.natural_height);
            const cell_w: f32 = @floatFromInt(sheet.cell_width);
            const cell_h: f32 = @floatFromInt(sheet.cell_height);
            const margin: f32 = @floatFromInt(sheet.margin);
            const padding: f32 = @floatFromInt(sheet.padding);

            // Cell UV dimensions
            const cell_u = cell_w / tex_w;
            const cell_v = cell_h / tex_h;

            // Starting offset (margin + cell position with padding)
            const start_u = (margin + @as(f32, @floatFromInt(col)) * (cell_w + padding)) / tex_w;
            const start_v = (margin + @as(f32, @floatFromInt(row)) * (cell_h + padding)) / tex_h;

            uv_min = .{ start_u, start_v };
            uv_max = .{ start_u + cell_u, start_v + cell_v };
        }

        // Apply flip by swapping UV coordinates
        if (sprite.flip_x) {
            const tmp = uv_min[0];
            uv_min[0] = uv_max[0];
            uv_max[0] = tmp;
        }
        if (sprite.flip_y) {
            const tmp = uv_min[1];
            uv_min[1] = uv_max[1];
            uv_max[1] = tmp;
        }

        // Calculate display size
        var w: f32 = if (sprite.width > 0) sprite.width else @floatFromInt(ref.natural_width);
        var h: f32 = if (sprite.height > 0) sprite.height else @floatFromInt(ref.natural_height);

        // If using sprite sheet with size=0, use cell size instead of full texture
        if (sprite.width == 0 and sprite.height == 0) {
            if (query.getOptional(entity, SpriteSheet)) |sheet| {
                w = @floatFromInt(sheet.cell_width);
                h = @floatFromInt(sheet.cell_height);
            }
        }

        // Apply scale component if present
        if (scale) |s| {
            w *= s.x;
            h *= s.y;
        }

        // Calculate position with anchor offset
        const x = transform.x - w * sprite.anchor_x;
        const y = transform.y - h * sprite.anchor_y;
        const z = transform.z;

        // Draw textured quad
        sokol.gl.enableTexture();
        sokol.gl.texture(ref.cached_view, ref.cached_sampler);
        sokol.gl.c4f(color.r, color.g, color.b, color.a);

        sokol.gl.beginQuads();
        // Top-left
        sokol.gl.t2f(uv_min[0], uv_min[1]);
        sokol.gl.v3f(x, y, z);
        // Top-right
        sokol.gl.t2f(uv_max[0], uv_min[1]);
        sokol.gl.v3f(x + w, y, z);
        // Bottom-right
        sokol.gl.t2f(uv_max[0], uv_max[1]);
        sokol.gl.v3f(x + w, y + h, z);
        // Bottom-left
        sokol.gl.t2f(uv_min[0], uv_max[1]);
        sokol.gl.v3f(x, y + h, z);
        sokol.gl.end();

        sokol.gl.disableTexture();
    }
}

// =============================================================================
// Plugin Definition
// =============================================================================

pub const Components = .{
    Sprite,
    TextureRef,
    SpriteSheet,
    SpriteIndex,
};

pub const Resources = .{};

pub const Events = .{};

/// SpritePlugin depends on RenderContextPlugin (for sokol.gl setup) and
/// AssetPlugin (for texture loading and AssetRegistry).
pub const Requires = .{ RenderContextPlugin, AssetPlugin };

pub const systems = .{
    .main = &.{
        // Resolve texture handles before rendering
        // Runs in pre_render stage (which always runs before render stage)
        .{
            .system = resolveTextureRefs,
            .stage = .pre_render,
            .config = .{
                .priority = 50,
                .tags = &.{"sprite-resolve"},
            },
        },
        // Draw sprites after GraphicsPlugin shapes but before sokol.gl.draw()
        // GraphicsPlugin draw2D is at priority 120
        // Note: .after constraints only work within the same stage, so we rely
        // on stage ordering (pre_render runs before render) for resolveTextureRefs
        .{
            .system = drawSprites,
            .stage = .render,
            .config = .{
                .priority = 115,
                .tags = &.{"sprite-render"},
            },
        },
    },
};
