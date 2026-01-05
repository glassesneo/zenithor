const std = @import("std");

/// Cache eviction policy
pub const CachePolicy = enum {
    lru, // Least Recently Used
    fifo, // First In First Out
    none, // No automatic eviction
};

/// IO and cache configuration
pub const IoConfig = struct {
    asset_root: [:0]const u8,
    use_embedded: bool = false,
    allow_filesystem: bool = true,
    allow_http_fallback: bool = false, // WASM only
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
