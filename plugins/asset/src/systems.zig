const std = @import("std");
const log = std.log.scoped(.asset);
const sparze = @import("sparze");
const sokol = @import("sokol");

const registry_mod = @import("registry.zig");
const loader_mod = @import("loader.zig");
const events_mod = @import("events.zig");
const config_mod = @import("config.zig");
const texture_loader = @import("loaders/texture.zig");

pub const AssetRegistry = registry_mod.AssetRegistry;
pub const AssetState = registry_mod.AssetState;
pub const LoaderRegistry = loader_mod.LoaderRegistry;
pub const JobPipeline = loader_mod.JobPipeline;
pub const LoadJob = loader_mod.LoadJob;
pub const JobData = loader_mod.JobData;
pub const LoadContext = loader_mod.LoadContext;
pub const IoConfig = config_mod.IoConfig;
pub const AssetStats = config_mod.AssetStats;

pub const AssetRequest = events_mod.AssetRequest;
pub const AssetLoaded = events_mod.AssetLoaded;
pub const AssetFailed = events_mod.AssetFailed;

/// Initialize asset system resources
/// Note: AssetRegistry, LoaderRegistry, JobPipeline, IoConfig, and AssetStats
/// are now auto-initialized by Sparze's Resource system via their init() methods.
/// This system only registers built-in loaders.
pub fn initRegistry(loader_registry: sparze.ResourceMut(LoaderRegistry)) void {
    // Register built-in loaders
    const texture_vtable = loader_mod.makeLoaderVTable(texture_loader.TextureLoader);
    loader_registry.registerLoader(texture_loader.Texture, texture_vtable) catch {
        log.err("Failed to register texture loader", .{});
    };

    log.info("Initialized asset management system", .{});
}

/// Process IO jobs (read files from disk or embedded assets)
pub fn pumpIoJobs(
    registry: sparze.ResourceMut(AssetRegistry),
    loaders: sparze.Resource(LoaderRegistry),
    pipeline: sparze.ResourceMut(JobPipeline),
    io_config: sparze.Resource(IoConfig),
    embedded: sparze.Resource(config_mod.EmbeddedAssets),
    stats: sparze.ResourceMut(AssetStats),
    requests: sparze.EventReader(AssetRequest),
    loaded_writer: sparze.EventWriter(AssetLoaded),
    failed_writer: sparze.EventWriter(AssetFailed),
) !void {
    var start_tick: u64 = 0;
    _ = sokol.time.laptime(&start_tick);

    // Process new asset requests
    for (requests.read()) |request| {
        const id = registry_mod.AssetId{
            .type_id = request.type_id,
            .path_hash = registry_mod.AssetId.hashPathWithSource(request.path, request.source),
        };

        // Check if asset already exists
        if (registry.getEntry(id)) |entry| {
            if (entry.state == .ready) {
                // Already loaded, emit immediate success
                try loaded_writer.enqueue(.{
                    .handle = .{ .id = id, .generation = entry.generation },
                    .type_id = request.type_id,
                });
                stats.cache_hits += 1;
                continue;
            } else if (entry.state.isLoading()) {
                // Already loading, skip duplicate request
                continue;
            }
        }

        // New request - create entry and enqueue IO job
        const entry = try registry.getOrCreateEntry(id);
        entry.state = .queued;
        stats.cache_misses += 1;

        const handle = registry_mod.AssetHandle{
            .id = id,
            .generation = entry.generation,
        };

        // Create IO job with explicit source
        const path_copy = try pipeline.allocator.dupe(u8, request.path);
        const job = LoadJob.init(handle, request.priority, .{
            .io = .{
                .path = path_copy,
                .source = request.source,
            },
        });

        try pipeline.enqueueIo(job);
    }

    // Process IO queue within budget
    var jobs_processed: usize = 0;
    while (pipeline.io_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_config.io_budget_us))) break;

        const job = pipeline.io_queue.orderedRemove(0);

        // Update entry state
        if (registry.getEntry(job.handle.id)) |entry| {
            entry.state = .io;
        }

        // Try to load asset data using explicit source
        const path = job.data.io.path;
        const source = job.data.io.source;
        const load_result = loadAssetData(pipeline.allocator, io_config, embedded, source, path);

        if (load_result) |bytes| {
            // Get loader for this type
            if (loaders.getLoaderById(job.handle.id.type_id)) |loader_vtable| {
                // Move to decode queue
                const decode_job = LoadJob.init(job.handle, job.priority, .{
                    .decode = .{
                        .bytes = bytes,
                        .loader = loader_vtable,
                    },
                });
                try pipeline.enqueueDecode(decode_job);
                jobs_processed += 1;
            } else {
                // No loader found
                try emitLoadFailure(
                    registry,
                    failed_writer,
                    job.handle,
                    .unsupported_format,
                    0,
                );
                pipeline.allocator.free(bytes);
            }
        } else |err| {
            // IO error - map to appropriate error kind
            const error_kind: registry_mod.AssetErrorKind = switch (err) {
                error.FileNotFound => .not_found,
                error.SourceUnavailable => .source_unavailable,
                error.AccessDenied, error.IoError, error.IncompleteRead, error.FileTooLarge, error.OutOfMemory => .io_error,
            };

            try emitLoadFailure(registry, failed_writer, job.handle, error_kind, job.retry_count);
        }

        // Free path
        pipeline.allocator.free(path);
    }

    if (jobs_processed > 0) {
        stats.loading_assets += jobs_processed;
    }
}

/// Process decode jobs (parse asset data)
pub fn pumpDecodeJobs(
    registry: sparze.ResourceMut(AssetRegistry),
    pipeline: sparze.ResourceMut(JobPipeline),
    io_config: sparze.Resource(IoConfig),
    failed_writer: sparze.EventWriter(AssetFailed),
) !void {
    var start_tick: u64 = 0;
    _ = sokol.time.laptime(&start_tick);

    var jobs_processed: usize = 0;
    while (pipeline.decode_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_config.decode_budget_us))) break;

        const job = pipeline.decode_queue.orderedRemove(0);

        // Update entry state
        if (registry.getEntry(job.handle.id)) |entry| {
            entry.state = .decode;
        }

        // Decode asset
        const bytes = job.data.decode.bytes;
        const loader = job.data.decode.loader;

        const ctx = LoadContext{
            .allocator = pipeline.allocator,
            .asset_id = job.handle.id,
        };

        if (loader.startLoad(bytes, ctx)) |payload| {
            // Move to upload queue
            const upload_job = LoadJob.init(job.handle, job.priority, .{
                .upload = .{
                    .parsed = payload,
                    .loader = loader,
                },
            });
            try pipeline.enqueueUpload(upload_job);
            jobs_processed += 1;
        } else |_| {
            // Decode failed
            try emitLoadFailure(registry, failed_writer, job.handle, .decode_failed, job.retry_count);
        }

        // Free bytes after decode
        pipeline.allocator.free(bytes);
    }
}

/// Process upload jobs (create GPU resources and finalize)
pub fn pumpUploadJobs(
    registry: sparze.ResourceMut(AssetRegistry),
    pipeline: sparze.ResourceMut(JobPipeline),
    io_config: sparze.Resource(IoConfig),
    stats: sparze.ResourceMut(AssetStats),
    loaded_writer: sparze.EventWriter(AssetLoaded),
    failed_writer: sparze.EventWriter(AssetFailed),
) !void {
    var start_tick: u64 = 0;
    _ = sokol.time.laptime(&start_tick);

    var jobs_processed: usize = 0;
    while (pipeline.upload_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_config.upload_budget_us))) break;

        const job = pipeline.upload_queue.orderedRemove(0);

        // Update entry state
        if (registry.getEntry(job.handle.id)) |entry| {
            entry.state = .upload;
        }

        const payload = job.data.upload.parsed;
        const loader = job.data.upload.loader;

        // Get memory usage
        const memory = loader.getMemoryUsage(payload);

        // Store payload in registry
        registry.setPayload(job.handle.id, payload, memory) catch {
            // Upload failed (shouldn't happen for non-GPU assets)
            loader.destroy(payload, pipeline.allocator);
            try emitLoadFailure(registry, failed_writer, job.handle, .gpu_upload_failed, job.retry_count);
            continue;
        };

        // Update stats
        stats.ready_assets += 1;
        stats.loading_assets -= 1;
        stats.total_assets += 1;

        // Emit success event
        try loaded_writer.enqueue(.{
            .handle = job.handle,
            .type_id = job.handle.id.type_id,
        });

        jobs_processed += 1;
    }
}

/// Cleanup and release all assets on shutdown
/// Note: Resource deinit() methods are now called automatically by Sparze's World.deinit().
/// This system only handles clearing job queues and destroying loaded asset payloads.
pub fn flushAndRelease(
    registry: sparze.ResourceMut(AssetRegistry),
    loaders: sparze.Resource(LoaderRegistry),
    pipeline: sparze.ResourceMut(JobPipeline),
) void {
    log.info("Flushing and releasing all assets", .{});

    // Clear all queues and free job-specific allocations
    for (pipeline.io_queue.items) |job| {
        pipeline.allocator.free(job.data.io.path);
    }
    pipeline.io_queue.clearRetainingCapacity();

    for (pipeline.decode_queue.items) |job| {
        pipeline.allocator.free(job.data.decode.bytes);
    }
    pipeline.decode_queue.clearRetainingCapacity();

    for (pipeline.upload_queue.items) |job| {
        const loader = job.data.upload.loader;
        loader.destroy(job.data.upload.parsed, pipeline.allocator);
    }
    pipeline.upload_queue.clearRetainingCapacity();

    // Destroy all loaded asset payloads
    var it = registry.entries.iterator();
    while (it.next()) |kv| {
        const entry = kv.value_ptr;
        if (entry.payload) |payload| {
            if (loaders.getLoaderById(kv.key_ptr.type_id)) |loader| {
                loader.destroy(payload, registry.allocator);
            }
            entry.payload = null;
        }
    }

    // Note: registry.deinit() and pipeline.deinit() are called automatically
    // by Sparze's World.deinit() via the auto-deinit system
}

// Helper functions

/// Custom errors for asset loading
const LoadError = error{
    FileNotFound,
    SourceUnavailable,
    FileTooLarge,
    IncompleteRead,
    OutOfMemory,
    AccessDenied,
    IoError,
};

/// Load asset data based on explicit source
fn loadAssetData(
    allocator: std.mem.Allocator,
    io_config: *const IoConfig,
    embedded: *const config_mod.EmbeddedAssets,
    source: config_mod.AssetSource,
    path: []const u8,
) LoadError![]u8 {
    const builtin = @import("builtin");

    switch (source) {
        .embedded => {
            if (embedded.get(path)) |data| {
                // Copy embedded data to allocator (caller expects to own and free it)
                const buffer = allocator.alloc(u8, data.len) catch return error.OutOfMemory;
                @memcpy(buffer, data);
                return buffer;
            }
            return error.FileNotFound;
        },
        .filesystem => {
            // Block filesystem access on WASM
            if (builtin.target.cpu.arch.isWasm()) {
                return error.SourceUnavailable;
            }
            return readFile(allocator, io_config.asset_root, path);
        },
    }
}

fn readFile(allocator: std.mem.Allocator, asset_root: [:0]const u8, path: []const u8) LoadError![]u8 {
    // Build full path
    const full_path = std.fs.path.join(allocator, &.{ asset_root, path }) catch return error.OutOfMemory;
    defer allocator.free(full_path);

    // Open file - preserve distinct error types
    const file = std.fs.cwd().openFile(full_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        else => return error.IoError,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return error.IoError;
    // Bounds check for 32-bit platforms (WASM)
    if (file_size > std.math.maxInt(usize)) return error.FileTooLarge;
    const size: usize = @intCast(file_size);
    const buffer = allocator.alloc(u8, size) catch return error.OutOfMemory;
    errdefer allocator.free(buffer);

    const bytes_read = file.readAll(buffer) catch return error.IoError;
    if (bytes_read != size) {
        return error.IncompleteRead;
    }

    return buffer;
}

fn emitLoadFailure(
    registry: sparze.ResourceMut(AssetRegistry),
    failed_writer: sparze.EventWriter(AssetFailed),
    handle: registry_mod.AssetHandle,
    error_kind: registry_mod.AssetErrorKind,
    retry_count: u8,
) !void {
    // Update entry state
    if (registry.getEntry(handle.id)) |entry| {
        entry.state = .failed;
        entry.last_error = .{
            .kind = error_kind,
            .message = @tagName(error_kind),
        };
    }

    // Emit failure event
    try failed_writer.enqueue(.{
        .handle = handle,
        .error_kind = error_kind,
        .retry_count = retry_count,
        .fallback_used = false,
    });
}
