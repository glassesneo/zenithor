const std = @import("std");
const registry = @import("registry.zig");
const config_mod = @import("config.zig");

pub const AssetId = registry.AssetId;
pub const AssetHandle = registry.AssetHandle;
pub const MemoryStats = registry.MemoryStats;

/// Context provided to loaders during load/reload
pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    asset_id: AssetId,
};

/// Virtual table for asset loaders
pub const LoaderVTable = struct {
    /// Check if this loader can handle a file path
    canLoad: *const fn (path: []const u8) bool,

    /// Load asset from bytes (initial load)
    startLoad: *const fn (bytes: []const u8, ctx: LoadContext) anyerror!*anyopaque,

    /// Reload asset (hot reload)
    reload: *const fn (old: *anyopaque, bytes: []const u8, ctx: LoadContext) anyerror!*anyopaque,

    /// Destroy asset and free resources
    destroy: *const fn (payload: *anyopaque, allocator: std.mem.Allocator) void,

    /// Get memory usage of asset
    getMemoryUsage: *const fn (payload: *anyopaque) MemoryStats,
};

/// Job stages in the loading pipeline
pub const JobStage = enum {
    io,
    decode,
    upload,
};

/// Data for each job stage
pub const JobData = union(JobStage) {
    io: struct {
        path: []const u8,
        source: config_mod.AssetSource, // Explicit source for loading
        buffer: ?[]u8 = null,
    },
    decode: struct {
        bytes: []u8,
        loader: LoaderVTable,
    },
    upload: struct {
        parsed: *anyopaque,
        loader: LoaderVTable,
    },
};

/// A loading job in the pipeline
pub const LoadJob = struct {
    handle: AssetHandle,
    priority: u8, // 0 = low, 255 = critical
    stage: JobStage,
    data: JobData,
    started_at: u64,
    retry_count: u8 = 0,

    pub fn init(handle: AssetHandle, priority: u8, data: JobData) LoadJob {
        return .{
            .handle = handle,
            .priority = priority,
            .stage = data,
            .data = data,
            .started_at = 0,
        };
    }
};

/// Job pipeline with per-stage queues
pub const JobPipeline = struct {
    io_queue: std.ArrayList(LoadJob),
    decode_queue: std.ArrayList(LoadJob),
    upload_queue: std.ArrayList(LoadJob),

    // Per-frame budgets (microseconds)
    io_budget_us: u64,
    decode_budget_us: u64,
    upload_budget_us: u64,

    allocator: std.mem.Allocator,

    /// Auto-init compatible signature: fn(Allocator) T
    pub fn init(allocator: std.mem.Allocator) JobPipeline {
        return .{
            .io_queue = .{},
            .decode_queue = .{},
            .upload_queue = .{},
            .io_budget_us = 2000,
            .decode_budget_us = 3000,
            .upload_budget_us = 1000,
            .allocator = allocator,
        };
    }

    /// Auto-deinit compatible signature: fn(*T, Allocator) void
    pub fn deinit(self: *JobPipeline, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.io_queue.deinit(self.allocator);
        self.decode_queue.deinit(self.allocator);
        self.upload_queue.deinit(self.allocator);
    }

    /// Enqueue an IO job
    pub fn enqueueIo(self: *JobPipeline, job: LoadJob) !void {
        try self.io_queue.append(self.allocator, job);
        self.sortByPriority(&self.io_queue);
    }

    /// Enqueue a decode job
    pub fn enqueueDecode(self: *JobPipeline, job: LoadJob) !void {
        try self.decode_queue.append(self.allocator, job);
        self.sortByPriority(&self.decode_queue);
    }

    /// Enqueue an upload job
    pub fn enqueueUpload(self: *JobPipeline, job: LoadJob) !void {
        try self.upload_queue.append(self.allocator, job);
        self.sortByPriority(&self.upload_queue);
    }

    /// Sort queue by priority (higher priority first)
    fn sortByPriority(self: *JobPipeline, queue: *std.ArrayList(LoadJob)) void {
        _ = self;
        std.mem.sort(LoadJob, queue.items, {}, struct {
            fn lessThan(_: void, a: LoadJob, b: LoadJob) bool {
                return a.priority > b.priority;
            }
        }.lessThan);
    }

    /// Check if any jobs are pending
    pub fn hasPendingJobs(self: *const JobPipeline) bool {
        return self.io_queue.items.len > 0 or
            self.decode_queue.items.len > 0 or
            self.upload_queue.items.len > 0;
    }
};

/// Registry of asset loaders by type
pub const LoaderRegistry = struct {
    loaders: std.AutoHashMap(u32, LoaderVTable), // type_id → vtable
    allocator: std.mem.Allocator,

    /// Auto-init compatible signature: fn(Allocator) T
    pub fn init(allocator: std.mem.Allocator) LoaderRegistry {
        return .{
            .loaders = std.AutoHashMap(u32, LoaderVTable).init(allocator),
            .allocator = allocator,
        };
    }

    /// Auto-deinit compatible signature: fn(*T, Allocator) void
    pub fn deinit(self: *LoaderRegistry, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.loaders.deinit();
    }

    /// Register a loader for a type
    pub fn registerLoader(self: *LoaderRegistry, comptime T: type, vtable: LoaderVTable) !void {
        const type_id = comptime AssetId.typeId(T);
        try self.loaders.put(type_id, vtable);
    }

    /// Get loader for a type
    pub fn getLoader(self: *const LoaderRegistry, comptime T: type) ?LoaderVTable {
        const type_id = comptime AssetId.typeId(T);
        return self.loaders.get(type_id);
    }

    /// Get loader by type_id
    pub fn getLoaderById(self: *const LoaderRegistry, type_id: u32) ?LoaderVTable {
        return self.loaders.get(type_id);
    }
};

/// Helper to create a loader vtable from a loader implementation
pub fn makeLoaderVTable(comptime Loader: type) LoaderVTable {
    const impl = struct {
        fn canLoad(path: []const u8) bool {
            return Loader.canLoad(path);
        }

        fn startLoad(bytes: []const u8, ctx: LoadContext) anyerror!*anyopaque {
            const result = try Loader.load(bytes, ctx.allocator);
            return @ptrCast(result);
        }

        fn reload(old: *anyopaque, bytes: []const u8, ctx: LoadContext) anyerror!*anyopaque {
            const typed_old: *Loader.AssetType = @ptrCast(@alignCast(old));
            if (@hasDecl(Loader, "reload")) {
                const result = try Loader.reload(typed_old, bytes, ctx.allocator);
                return @ptrCast(result);
            } else {
                // Default: destroy old and load new
                Loader.destroy(typed_old, ctx.allocator);
                const result = try Loader.load(bytes, ctx.allocator);
                return @ptrCast(result);
            }
        }

        fn destroy(payload: *anyopaque, allocator: std.mem.Allocator) void {
            const typed: *Loader.AssetType = @ptrCast(@alignCast(payload));
            Loader.destroy(typed, allocator);
        }

        fn getMemoryUsage(payload: *anyopaque) MemoryStats {
            const typed: *Loader.AssetType = @ptrCast(@alignCast(payload));
            if (@hasDecl(Loader, "getMemoryUsage")) {
                return Loader.getMemoryUsage(typed);
            } else {
                return .{};
            }
        }
    };

    return .{
        .canLoad = impl.canLoad,
        .startLoad = impl.startLoad,
        .reload = impl.reload,
        .destroy = impl.destroy,
        .getMemoryUsage = impl.getMemoryUsage,
    };
}

test "LoaderRegistry operations" {
    const TestAsset = struct {
        value: u32,
    };

    const TestLoader = struct {
        pub const AssetType = TestAsset;

        pub fn canLoad(path: []const u8) bool {
            return std.mem.endsWith(u8, path, ".test");
        }

        pub fn load(bytes: []const u8, allocator: std.mem.Allocator) !*TestAsset {
            _ = bytes;
            const asset = try allocator.create(TestAsset);
            asset.* = .{ .value = 42 };
            return asset;
        }

        pub fn destroy(asset: *TestAsset, allocator: std.mem.Allocator) void {
            allocator.destroy(asset);
        }
    };

    var loader_registry = LoaderRegistry.init(std.testing.allocator);
    defer loader_registry.deinit(std.testing.allocator);

    const vtable = makeLoaderVTable(TestLoader);
    try loader_registry.registerLoader(TestAsset, vtable);

    const retrieved = loader_registry.getLoader(TestAsset);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.canLoad("test.test"));
    try std.testing.expect(!retrieved.?.canLoad("test.other"));
}

test "JobPipeline priority sorting" {
    var pipeline = JobPipeline.init(std.testing.allocator);
    defer pipeline.deinit(std.testing.allocator);

    const id = AssetId.init(u32, "test");
    const handle = AssetHandle{ .id = id, .generation = 0 };

    try pipeline.enqueueIo(LoadJob.init(handle, 100, .{ .io = .{ .path = "a" } }));
    try pipeline.enqueueIo(LoadJob.init(handle, 200, .{ .io = .{ .path = "b" } }));
    try pipeline.enqueueIo(LoadJob.init(handle, 50, .{ .io = .{ .path = "c" } }));

    // Should be sorted by priority: 200, 100, 50
    try std.testing.expectEqual(@as(u8, 200), pipeline.io_queue.items[0].priority);
    try std.testing.expectEqual(@as(u8, 100), pipeline.io_queue.items[1].priority);
    try std.testing.expectEqual(@as(u8, 50), pipeline.io_queue.items[2].priority);
}
