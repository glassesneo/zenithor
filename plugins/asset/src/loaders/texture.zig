const std = @import("std");
const registry = @import("../registry.zig");
const sokol = @import("sokol");

/// Loaded texture asset with GPU image handle
pub const Texture = struct {
    /// Decoded RGBA pixel data (CPU-side, kept for potential re-uploads)
    pixels: []const u8,
    width: u32,
    height: u32,
    /// GPU texture handle
    image: sokol.gfx.Image = .{},
    /// Sampler for texture filtering
    sampler: sokol.gfx.Sampler = .{},
    /// Cached view for sokol.gl.texture() - created once, reused every frame
    view: sokol.gfx.View = .{},

    pub fn deinit(self: *Texture, allocator: std.mem.Allocator) void {
        // Destroy GPU resources in reverse creation order
        if (self.view.id != 0) {
            sokol.gfx.destroyView(self.view);
        }
        if (self.sampler.id != 0) {
            sokol.gfx.destroySampler(self.sampler);
        }
        if (self.image.id != 0) {
            sokol.gfx.destroyImage(self.image);
        }
        // Free CPU pixel data
        allocator.free(self.pixels);
    }
};

/// Texture loader implementation with PNG decoding
/// Note: Only PNG format is currently supported. JPEG support may be added in the future.
pub const TextureLoader = struct {
    pub const AssetType = Texture;

    pub fn canLoad(path: []const u8) bool {
        return std.mem.endsWith(u8, path, ".png");
    }

    pub fn load(bytes: []const u8, allocator: std.mem.Allocator) !*Texture {
        // Decode PNG to RGBA pixels
        const decoded = try decodePng(bytes, allocator);
        errdefer allocator.free(decoded.pixels);

        // Allocate texture struct FIRST to avoid GPU resource leaks on OOM
        const texture = try allocator.create(Texture);
        errdefer allocator.destroy(texture);

        // Create GPU image
        var image_desc = sokol.gfx.ImageDesc{
            .width = @intCast(decoded.width),
            .height = @intCast(decoded.height),
            .pixel_format = .RGBA8,
        };
        image_desc.data.mip_levels[0] = .{
            .ptr = decoded.pixels.ptr,
            .size = decoded.pixels.len,
        };
        const image = sokol.gfx.makeImage(image_desc);
        errdefer sokol.gfx.destroyImage(image);

        // Create sampler with nearest filtering (good for pixel art)
        const sampler = sokol.gfx.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
        errdefer sokol.gfx.destroySampler(sampler);

        // Create cached view for sokol.gl (created once, not per-frame)
        const view = sokol.gfx.makeView(.{
            .texture = .{ .image = image },
        });
        // No errdefer needed for view - if we reach here, assignment will succeed

        texture.* = .{
            .pixels = decoded.pixels,
            .width = decoded.width,
            .height = decoded.height,
            .image = image,
            .sampler = sampler,
            .view = view,
        };

        std.debug.print("[Texture] Loaded {d}x{d} texture (GPU image id: {d})\n", .{
            decoded.width,
            decoded.height,
            image.id,
        });

        return texture;
    }

    pub fn destroy(texture: *Texture, allocator: std.mem.Allocator) void {
        texture.deinit(allocator);
        allocator.destroy(texture);
    }

    pub fn getMemoryUsage(texture: *Texture) registry.MemoryStats {
        const cpu_bytes = @sizeOf(Texture) + texture.pixels.len;
        // Use checked multiply for GPU bytes (shouldn't overflow if load succeeded)
        const pixel_count = std.math.mul(usize, texture.width, texture.height) catch 0;
        const gpu_bytes = std.math.mul(usize, pixel_count, 4) catch 0; // RGBA
        return .{
            .cpu_bytes = cpu_bytes,
            .gpu_bytes = gpu_bytes,
        };
    }
};

/// Decoded PNG result
const DecodedImage = struct {
    pixels: []u8,
    width: u32,
    height: u32,
};

/// Minimal PNG decoder supporting our 8x8 checkerboard test image
/// Supports: 8-bit RGBA, non-interlaced, zlib compressed
fn decodePng(data: []const u8, allocator: std.mem.Allocator) !DecodedImage {
    // PNG signature check
    const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    if (data.len < 8 or !std.mem.eql(u8, data[0..8], &png_signature)) {
        return error.InvalidPngSignature;
    }

    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: u8 = 0;
    var color_type: u8 = 0;
    var idat_data: std.ArrayListUnmanaged(u8) = .empty;
    defer idat_data.deinit(allocator);

    // Parse chunks
    var pos: usize = 8;
    while (pos + 12 <= data.len) {
        const chunk_len = std.mem.readInt(u32, data[pos..][0..4], .big);
        // Bounds check BEFORE slicing chunk data
        if (pos + 12 + chunk_len > data.len) return error.InvalidChunkLength;

        const chunk_type = data[pos + 4 ..][0..4];
        const chunk_data = data[pos + 8 ..][0..chunk_len];
        pos += 12 + chunk_len;

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            // IHDR must be at least 13 bytes
            if (chunk_len < 13) return error.InvalidIHDRLength;
            width = std.mem.readInt(u32, chunk_data[0..4], .big);
            height = std.mem.readInt(u32, chunk_data[4..8], .big);
            bit_depth = chunk_data[8];
            color_type = chunk_data[9];
            // chunk_data[10] = compression (always 0)
            // chunk_data[11] = filter (always 0)
            // chunk_data[12] = interlace (we only support 0)
            if (chunk_data[12] != 0) return error.InterlacedNotSupported;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            try idat_data.appendSlice(allocator, chunk_data);
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }
    }

    if (width == 0 or height == 0) return error.InvalidPngHeader;
    if (bit_depth != 8) return error.UnsupportedBitDepth;
    if (color_type != 6) return error.UnsupportedColorType; // We only support RGBA

    // Decompress zlib data using flate
    const decompressed = try decompressZlib(idat_data.items, allocator);
    defer allocator.free(decompressed);

    // Use checked arithmetic for all size calculations to prevent overflow
    const width_usize: usize = @intCast(width);
    const height_usize: usize = @intCast(height);
    const bytes_per_pixel: usize = 4; // RGBA

    const bytes_per_row = std.math.mul(usize, width_usize, bytes_per_pixel) catch return error.ImageTooLarge;
    const row_with_filter = std.math.add(usize, bytes_per_row, 1) catch return error.ImageTooLarge;
    const expected_len = std.math.mul(usize, height_usize, row_with_filter) catch return error.ImageTooLarge;
    if (decompressed.len != expected_len) return error.InvalidDecompressedSize;

    // Allocate output pixels with overflow check
    const pixel_count = std.math.mul(usize, width_usize, height_usize) catch return error.ImageTooLarge;
    const pixel_bytes = std.math.mul(usize, pixel_count, bytes_per_pixel) catch return error.ImageTooLarge;
    const pixels = try allocator.alloc(u8, pixel_bytes);
    errdefer allocator.free(pixels);

    // Apply PNG filters and extract pixels
    var prev_row: ?[]const u8 = null;
    for (0..height_usize) |y| {
        const row_start = y * row_with_filter;
        const filter_byte = decompressed[row_start];
        const filtered_row = decompressed[row_start + 1 ..][0..bytes_per_row];
        const output_row = pixels[y * bytes_per_row ..][0..bytes_per_row];

        try applyPngFilter(filter_byte, filtered_row, prev_row, output_row, 4);
        prev_row = output_row;
    }

    return .{
        .pixels = pixels,
        .width = width,
        .height = height,
    };
}

/// Apply PNG row filter
fn applyPngFilter(filter: u8, data: []const u8, prev_row: ?[]const u8, output: []u8, bpp: usize) !void {
    switch (filter) {
        0 => { // None
            @memcpy(output, data);
        },
        1 => { // Sub
            for (0..data.len) |i| {
                const a: u8 = if (i >= bpp) output[i - bpp] else 0;
                output[i] = data[i] +% a;
            }
        },
        2 => { // Up
            for (0..data.len) |i| {
                const b: u8 = if (prev_row) |pr| pr[i] else 0;
                output[i] = data[i] +% b;
            }
        },
        3 => { // Average
            for (0..data.len) |i| {
                const a: u16 = if (i >= bpp) output[i - bpp] else 0;
                const b: u16 = if (prev_row) |pr| pr[i] else 0;
                output[i] = data[i] +% @as(u8, @intCast((a + b) / 2));
            }
        },
        4 => { // Paeth
            for (0..data.len) |i| {
                const a: i16 = if (i >= bpp) output[i - bpp] else 0;
                const b: i16 = if (prev_row) |pr| pr[i] else 0;
                const c: i16 = if (i >= bpp and prev_row != null) prev_row.?[i - bpp] else 0;
                output[i] = data[i] +% paethPredictor(a, b, c);
            }
        },
        else => return error.UnsupportedFilter,
    }
}

fn paethPredictor(a: i16, b: i16, c: i16) u8 {
    const p = a + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return @intCast(@as(u16, @bitCast(a)) & 0xFF);
    if (pb <= pc) return @intCast(@as(u16, @bitCast(b)) & 0xFF);
    return @intCast(@as(u16, @bitCast(c)) & 0xFF);
}

/// Decompress zlib data (deflate with zlib header)
fn decompressZlib(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const flate = std.compress.flate;

    if (data.len < 6) return error.InvalidZlibData; // 2 header + 4 adler32

    // Create input reader from data
    var input = std.Io.Reader.fixed(data);

    // Buffer for decompression window (required for indirect mode)
    var window_buf: [flate.max_window_len]u8 = undefined;

    // Initialize decompressor with zlib container format
    var decomp = flate.Decompress.init(&input, .zlib, &window_buf);

    // Collect decompressed output using ArrayList writer
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    // Stream decompressed data in chunks
    var chunk_buf: [4096]u8 = undefined;
    while (true) {
        const n = decomp.reader.readSliceShort(&chunk_buf) catch |err| switch (err) {
            error.ReadFailed => {
                if (decomp.err) |e| {
                    if (e == error.EndOfStream) break;
                    return e;
                }
                return error.DecompressionFailed;
            },
        };
        if (n == 0) break;
        try result.appendSlice(allocator, chunk_buf[0..n]);
    }

    return result.toOwnedSlice(allocator);
}

test "decode simple PNG" {
    // This would test with actual PNG data
}
