const std = @import("std");

/// Cache eviction policy
pub const CachePolicy = enum {
    lru, // Least Recently Used
    fifo, // First In First Out
    none, // No automatic eviction
};

/// Explicit source for loading an individual asset.
/// Each asset request must specify where to load from.
pub const AssetSource = enum {
    /// Load from EmbeddedAssets registry (must be pre-registered via @embedFile)
    embedded,
    /// Load from filesystem under asset_root
    filesystem,
};

/// Locator specifying which asset to load and from where.
/// Use the constructor functions for a clean API.
pub const AssetLocator = struct {
    path: []const u8,
    source: AssetSource,

    /// Create locator for an embedded asset (registered via @embedFile)
    pub fn embedded(path: []const u8) AssetLocator {
        return .{ .path = path, .source = .embedded };
    }

    /// Create locator for a filesystem asset (under asset_root)
    pub fn filesystem(path: []const u8) AssetLocator {
        return .{ .path = path, .source = .filesystem };
    }
};

/// Registry for embedded asset data (compile-time embedded files)
/// Use this for WASM builds or to bundle critical assets with the binary.
/// Paths are normalized (lowercase, forward slashes) for consistent lookup.
pub const EmbeddedAssets = struct {
    /// Map of normalized path -> embedded bytes
    entries: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Allocator for storing normalized path keys
    key_allocator: ?std.mem.Allocator = null,

    pub fn init(allocator: std.mem.Allocator) EmbeddedAssets {
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *EmbeddedAssets, allocator: std.mem.Allocator) void {
        // Free normalized path keys we allocated
        var it = self.entries.keyIterator();
        while (it.next()) |key| {
            if (self.key_allocator) |key_alloc| {
                key_alloc.free(key.*);
            }
        }
        // Free hashmap buckets (entries point to compile-time data, no need to free values)
        self.entries.deinit(allocator);
    }

    /// Normalize a path: lowercase, forward slashes
    fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const normalized = try allocator.alloc(u8, path.len);
        for (path, 0..) |c, i| {
            normalized[i] = if (c == '\\') '/' else std.ascii.toLower(c);
        }
        return normalized;
    }

    /// Register an embedded asset (typically from @embedFile)
    /// Path is normalized for consistent lookup regardless of case/separators.
    pub fn register(self: *EmbeddedAssets, allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
        if (self.key_allocator == null) {
            self.key_allocator = allocator;
        }
        const normalized_path = try normalizePath(allocator, path);
        errdefer allocator.free(normalized_path);
        try self.entries.put(allocator, normalized_path, data);
    }

    /// Get embedded asset data by path (path is normalized before lookup)
    pub fn get(self: *const EmbeddedAssets, path: []const u8) ?[]const u8 {
        // Normalize path in-place for lookup (stack buffer)
        var normalized_buf: [512]u8 = undefined;
        if (path.len > normalized_buf.len) return null;
        for (path, 0..) |c, i| {
            normalized_buf[i] = if (c == '\\') '/' else std.ascii.toLower(c);
        }
        return self.entries.get(normalized_buf[0..path.len]);
    }
};

/// IO and cache configuration
pub const IoConfig = struct {
    /// Root directory for filesystem assets
    asset_root: [:0]const u8,
    /// Allow HTTP fallback for missing assets (WASM only, future feature)
    allow_http_fallback: bool = false,
    /// Prefetch asset manifest on startup
    prefetch_manifest: bool = true,

    // Memory limits (in MB)
    max_cpu_mb: usize = 512,
    max_gpu_mb: usize = 256,

    // Cache policy
    cache_policy: CachePolicy = .lru,
    keep_zero_refcount_secs: u32 = 30,

    // Per-frame budgets (microseconds)
    io_budget_us: u64 = 2000,
    decode_budget_us: u64 = 3000,
    upload_budget_us: u64 = 1000,

    // Retry policy
    max_retries: u8 = 3,
    retry_backoff_ms: u32 = 100,

    /// Auto-init compatible signature: fn(Allocator) T
    pub fn init(allocator: std.mem.Allocator) IoConfig {
        _ = allocator;
        return .{
            .asset_root = "assets",
        };
    }
};

/// Asset statistics for monitoring
pub const AssetStats = struct {
    total_cpu_bytes: usize = 0,
    total_gpu_bytes: usize = 0,
    total_assets: usize = 0,
    ready_assets: usize = 0,
    loading_assets: usize = 0,
    failed_assets: usize = 0,
    cache_hits: usize = 0,
    cache_misses: usize = 0,
    evictions: usize = 0,
};
