const std = @import("std");
const config_mod = @import("config.zig");

/// Unique identifier for an asset (stable across reloads)
/// Includes source to prevent cache collisions between embedded and filesystem assets with the same path.
pub const AssetId = struct {
    type_id: u32, // Hash of asset type
    path_hash: u64, // Hash of normalized path + source

    pub fn init(comptime T: type, path: []const u8, source: config_mod.AssetSource) AssetId {
        return .{
            .type_id = comptime typeId(T),
            .path_hash = hashPathWithSource(path, source),
        };
    }

    pub fn eql(self: AssetId, other: AssetId) bool {
        return self.type_id == other.type_id and self.path_hash == other.path_hash;
    }

    pub fn typeId(comptime T: type) u32 {
        const type_name = @typeName(T);
        return @truncate(std.hash.Wyhash.hash(0, type_name));
    }

    /// Hash path with source to ensure embedded and filesystem assets don't collide
    pub fn hashPathWithSource(path: []const u8, source: config_mod.AssetSource) u64 {
        var hasher = std.hash.Wyhash.init(0);
        // Include source as first byte to differentiate same paths with different sources
        hasher.update(&[_]u8{@intFromEnum(source)});
        // Normalize path (lowercase, forward slashes) for consistent hashing
        for (path) |c| {
            const normalized = if (c == '\\') '/' else std.ascii.toLower(c);
            hasher.update(&[_]u8{normalized});
        }
        return hasher.final();
    }
};

/// Versioned handle prevents use-after-free on reload
pub const AssetHandle = struct {
    id: AssetId,
    generation: u32, // Increments on reload/eviction

    pub fn eql(self: AssetHandle, other: AssetHandle) bool {
        return self.id.eql(other.id) and self.generation == other.generation;
    }
};

/// Generic typed wrapper for type-safe asset handles
pub fn TypedHandle(comptime T: type) type {
    _ = T; // Used for type safety only
    return struct {
        handle: AssetHandle,

        const Self = @This();

        pub fn init(id: AssetId, generation: u32) Self {
            return .{ .handle = .{ .id = id, .generation = generation } };
        }

        pub fn fromHandle(handle: AssetHandle) Self {
            return .{ .handle = handle };
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.handle.eql(other.handle);
        }
    };
}

/// Asset loading state
pub const AssetState = enum {
    unloaded,
    queued,
    io,
    decode,
    upload,
    ready,
    failed,

    pub fn isLoading(self: AssetState) bool {
        return self == .queued or self == .io or self == .decode or self == .upload;
    }

    pub fn isComplete(self: AssetState) bool {
        return self == .ready or self == .failed;
    }
};

/// Error types for asset loading
pub const AssetErrorKind = enum {
    not_found,
    decode_failed,
    io_error,
    gpu_upload_failed,
    unsupported_format,
    source_unavailable, // Requested source not available (e.g., filesystem on WASM)
};

pub const AssetError = struct {
    kind: AssetErrorKind,
    message: []const u8,
};

/// Eviction reasons for cache management
pub const EvictionReason = enum {
    low_memory,
    lru,
    explicit,
};

/// Memory statistics for an asset
pub const MemoryStats = struct {
    cpu_bytes: usize = 0,
    gpu_bytes: usize = 0,
};

/// Entry in the asset registry
pub const AssetEntry = struct {
    generation: u32,
    state: AssetState,
    payload: ?*anyopaque, // Pointer to loaded asset (T)
    refcount: u32,
    version: u32, // Hot reload version counter
    dependencies: []AssetId,
    last_error: ?AssetError,
    last_access: u64, // For LRU eviction
    memory: MemoryStats,

    pub fn init(generation: u32) AssetEntry {
        return .{
            .generation = generation,
            .state = .unloaded,
            .payload = null,
            .refcount = 0,
            .version = 0,
            .dependencies = &.{},
            .last_error = null,
            .last_access = 0,
            .memory = .{},
        };
    }
};

/// Central registry for all assets
pub const AssetRegistry = struct {
    entries: std.AutoHashMap(AssetId, AssetEntry),
    fallbacks: std.AutoHashMap(u32, AssetId), // type_id → fallback asset
    total_cpu_bytes: usize,
    total_gpu_bytes: usize,
    allocator: std.mem.Allocator,

    /// Auto-init compatible signature: fn(Allocator) T
    pub fn init(allocator: std.mem.Allocator) AssetRegistry {
        return .{
            .entries = std.AutoHashMap(AssetId, AssetEntry).init(allocator),
            .fallbacks = std.AutoHashMap(u32, AssetId).init(allocator),
            .total_cpu_bytes = 0,
            .total_gpu_bytes = 0,
            .allocator = allocator,
        };
    }

    /// Auto-deinit compatible signature: fn(*T, Allocator) void
    pub fn deinit(self: *AssetRegistry, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.entries.deinit();
        self.fallbacks.deinit();
    }

    /// Get or create an entry for an asset
    pub fn getOrCreateEntry(self: *AssetRegistry, id: AssetId) !*AssetEntry {
        const result = try self.entries.getOrPut(id);
        if (!result.found_existing) {
            result.value_ptr.* = AssetEntry.init(0);
        }
        return result.value_ptr;
    }

    /// Get an existing entry (mutable)
    pub fn getEntry(self: *AssetRegistry, id: AssetId) ?*AssetEntry {
        return self.entries.getPtr(id);
    }

    /// Get an existing entry (const)
    pub fn getEntryConst(self: *const AssetRegistry, id: AssetId) ?*const AssetEntry {
        return self.entries.getPtr(id);
    }

    /// Create a new handle for an asset
    pub fn createHandle(self: *AssetRegistry, comptime T: type, locator: config_mod.AssetLocator) !TypedHandle(T) {
        const id = AssetId.init(T, locator.path, locator.source);
        const entry = try self.getOrCreateEntry(id);
        return TypedHandle(T).init(id, entry.generation);
    }

    /// Validate a handle and get its entry
    pub fn validateHandle(self: *const AssetRegistry, handle: AssetHandle) ?*const AssetEntry {
        const entry = self.getEntryConst(handle.id) orelse return null;
        if (entry.generation != handle.generation) return null;
        return entry;
    }

    /// Set the payload for an asset
    pub fn setPayload(
        self: *AssetRegistry,
        id: AssetId,
        payload: *anyopaque,
        memory: MemoryStats,
    ) !void {
        const entry = self.getEntry(id) orelse return error.AssetNotFound;
        entry.payload = payload;
        entry.state = .ready;
        entry.memory = memory;

        self.total_cpu_bytes += memory.cpu_bytes;
        self.total_gpu_bytes += memory.gpu_bytes;
    }

    /// Increment refcount
    pub fn addRef(self: *AssetRegistry, id: AssetId) !void {
        const entry = try self.getOrCreateEntry(id);
        entry.refcount += 1;
    }

    /// Decrement refcount
    pub fn release(self: *AssetRegistry, id: AssetId) void {
        if (self.getEntry(id)) |entry| {
            if (entry.refcount > 0) {
                entry.refcount -= 1;
            }
        }
    }

    /// Set fallback asset for a type
    pub fn setFallback(self: *AssetRegistry, comptime T: type, id: AssetId) !void {
        const type_id = comptime AssetId.typeId(T);
        try self.fallbacks.put(type_id, id);
    }

    /// Get fallback asset for a type
    pub fn getFallback(self: *AssetRegistry, comptime T: type) ?AssetId {
        const type_id = comptime AssetId.typeId(T);
        return self.fallbacks.get(type_id);
    }

    /// Update memory tracking after eviction
    pub fn updateMemoryOnEvict(self: *AssetRegistry, memory: MemoryStats) void {
        self.total_cpu_bytes -= @min(self.total_cpu_bytes, memory.cpu_bytes);
        self.total_gpu_bytes -= @min(self.total_gpu_bytes, memory.gpu_bytes);
    }
};

test "AssetId hashing" {
    const T = struct {};
    const id1 = AssetId.init(T, "textures/player.png", .filesystem);
    const id2 = AssetId.init(T, "textures/player.png", .filesystem);
    const id3 = AssetId.init(T, "TEXTURES/PLAYER.PNG", .filesystem); // Different case
    const id4 = AssetId.init(T, "textures\\player.png", .filesystem); // Different separators
    const id5 = AssetId.init(T, "textures/player.png", .embedded); // Different source

    try std.testing.expect(id1.eql(id2));
    try std.testing.expect(id1.eql(id3)); // Case-insensitive
    try std.testing.expect(id1.eql(id4)); // Separator-insensitive
    try std.testing.expect(!id1.eql(id5)); // Different source should NOT match
}

test "AssetRegistry basic operations" {
    const T = struct {};
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit(std.testing.allocator);

    const locator = config_mod.AssetLocator.filesystem("test.asset");
    const handle = try registry.createHandle(T, locator);

    // Entry should exist
    const entry = registry.validateHandle(handle.handle);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(AssetState.unloaded, entry.?.state);

    // Refcounting
    try registry.addRef(handle.handle.id);
    try std.testing.expectEqual(@as(u32, 1), entry.?.refcount);

    registry.release(handle.handle.id);
    try std.testing.expectEqual(@as(u32, 0), entry.?.refcount);
}

test "Handle generation invalidation" {
    const T = struct {};
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit(std.testing.allocator);

    const handle = try registry.createHandle(T, config_mod.AssetLocator.filesystem("test.asset"));

    // Valid initially
    try std.testing.expect(registry.validateHandle(handle.handle) != null);

    // Increment generation (simulating reload/eviction)
    const entry = registry.getEntry(handle.handle.id).?;
    entry.generation += 1;

    // Handle should now be invalid
    try std.testing.expect(registry.validateHandle(handle.handle) == null);
}
