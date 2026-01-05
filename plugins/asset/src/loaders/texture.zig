const std = @import("std");
const registry = @import("../registry.zig");

/// Loaded texture asset (simplified - stores raw bytes for MVP)
pub const Texture = struct {
    bytes: []const u8,
    width: u32 = 256,  // Placeholder
    height: u32 = 256, // Placeholder

    pub fn deinit(self: *Texture, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

/// Texture loader implementation
pub const TextureLoader = struct {
    pub const AssetType = Texture;

    pub fn canLoad(path: []const u8) bool {
        return std.mem.endsWith(u8, path, ".png") or
            std.mem.endsWith(u8, path, ".jpg") or
            std.mem.endsWith(u8, path, ".jpeg");
    }

    pub fn load(bytes: []const u8, allocator: std.mem.Allocator) !*Texture {
        // For MVP: just store the raw bytes
        // TODO: Implement actual image decoding with stb_image
        const bytes_copy = try allocator.dupe(u8, bytes);

        const texture = try allocator.create(Texture);
        texture.* = .{
            .bytes = bytes_copy,
        };

        return texture;
    }

    pub fn destroy(texture: *Texture, allocator: std.mem.Allocator) void {
        texture.deinit(allocator);
        allocator.destroy(texture);
    }

    pub fn getMemoryUsage(texture: *Texture) registry.MemoryStats {
        const cpu_bytes = @sizeOf(Texture) + texture.bytes.len;
        const gpu_bytes: usize = 0; // No GPU upload in MVP
        return .{
            .cpu_bytes = cpu_bytes,
            .gpu_bytes = gpu_bytes,
        };
    }
};
