const std = @import("std");
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

/// Get appropriate allocator for current platform
fn getAllocator() std.mem.Allocator {
    const builtin = @import("builtin");
    return if (builtin.target.cpu.arch.isWasm())
        std.heap.c_allocator
    else
        std.heap.page_allocator;
}

/// Initialize asset system resources
/// Note: AssetRegistry, LoaderRegistry, JobPipeline, IoConfig, and AssetStats
/// are now auto-initialized by Sparze's Resource system via their init() methods.
/// This system only registers built-in loaders.
pub fn initRegistry(loader_registry: sparze.ResourceMut(LoaderRegistry)) void {
    // Register built-in loaders
    const texture_vtable = loader_mod.makeLoaderVTable(texture_loader.TextureLoader);
    loader_registryregisterLoader(texture_loader.Texture, texture_vtable) catch {
        std.debug.print("Failed to register texture loader\n", .{});
    };

    std.debug.print("[Asset] Initialized asset management system\n", .{});
}

/// Process IO jobs (read files from disk)
pub fn pumpIoJobs(
    registry: sparze.ResourceMut(AssetRegistry),
    loaders: sparze.Resource(LoaderRegistry),
    pipeline: sparze.ResourceMut(JobPipeline),
    io_config: sparze.Resource(IoConfig),
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
            .path_hash = registry_mod.AssetId.hashPath(request.path),
        };

        // Check if asset already exists
        if (registrygetEntry(id)) |entry| {
            if (entry.state == .ready) {
                // Already loaded, emit immediate success
                try loaded_writer.enqueue(.{
                    .handle = .{ .id = id, .generation = entry.generation },
                    .type_id = request.type_id,
                });
                statscache_hits += 1;
                continue;
            } else if (entry.state.isLoading()) {
                // Already loading, skip duplicate request
                continue;
            }
        }

        // New request - create entry and enqueue IO job
        const entry = try registrygetOrCreateEntry(id);
        entry.state = .queued;
        statscache_misses += 1;

        const handle = registry_mod.AssetHandle{
            .id = id,
            .generation = entry.generation,
        };

        // Create IO job
        const path_copy = try pipelineallocator.dupe(u8, request.path);
        const job = LoadJob.init(handle, request.priority, .{
            .io = .{ .path = path_copy },
        });

        try pipelineenqueueIo(job);
    }

    // Process IO queue within budget
    var jobs_processed: usize = 0;
    while (pipelineio_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_configio_budget_us))) break;

        const job = pipelineio_queue.orderedRemove(0);

        // Update entry state
        if (registrygetEntry(job.handle.id)) |entry| {
            entry.state = .io;
        }

        // Read file from disk
        const path = job.data.io.path;
        const file_result = readFile(pipelineallocator, io_configasset_root, path);

        if (file_result) |bytes| {
            // Get loader for this type
            if (loadersgetLoaderById(job.handle.id.type_id)) |loader_vtable| {
                // Move to decode queue
                const decode_job = LoadJob.init(job.handle, job.priority, .{
                    .decode = .{
                        .bytes = bytes,
                        .loader = loader_vtable,
                    },
                });
                try pipelineenqueueDecode(decode_job);
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
                pipelineallocator.free(bytes);
            }
        } else |err| {
            // IO error
            const error_kind: registry_mod.AssetErrorKind = switch (err) {
                error.FileNotFound => .not_found,
                else => .io_error,
            };

            try emitLoadFailure(registry, failed_writer, job.handle, error_kind, job.retry_count);
        }

        // Free path
        pipelineallocator.free(path);
    }

    if (jobs_processed > 0) {
        statsloading_assets += jobs_processed;
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
    while (pipelinedecode_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_configdecode_budget_us))) break;

        const job = pipelinedecode_queue.orderedRemove(0);

        // Update entry state
        if (registrygetEntry(job.handle.id)) |entry| {
            entry.state = .decode;
        }

        // Decode asset
        const bytes = job.data.decode.bytes;
        const loader = job.data.decode.loader;

        const ctx = LoadContext{
            .allocator = pipelineallocator,
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
            try pipelineenqueueUpload(upload_job);
            jobs_processed += 1;
        } else |_| {
            // Decode failed
            try emitLoadFailure(registry, failed_writer, job.handle, .decode_failed, job.retry_count);
        }

        // Free bytes after decode
        pipelineallocator.free(bytes);
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
    while (pipelineupload_queue.items.len > 0) {
        const elapsed_ticks = sokol.time.laptime(&start_tick);
        const elapsed_us = sokol.time.us(elapsed_ticks);
        if (elapsed_us >= @as(f64, @floatFromInt(io_configupload_budget_us))) break;

        const job = pipelineupload_queue.orderedRemove(0);

        // Update entry state
        if (registrygetEntry(job.handle.id)) |entry| {
            entry.state = .upload;
        }

        const payload = job.data.upload.parsed;
        const loader = job.data.upload.loader;

        // Get memory usage
        const memory = loader.getMemoryUsage(payload);

        // Store payload in registry
        registrysetPayload(job.handle.id, payload, memory) catch {
            // Upload failed (shouldn't happen for non-GPU assets)
            loader.destroy(payload, pipelineallocator);
            try emitLoadFailure(registry, failed_writer, job.handle, .gpu_upload_failed, job.retry_count);
            continue;
        };

        // Update stats
        statsready_assets += 1;
        statsloading_assets -= 1;
        statstotal_assets += 1;

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
    std.debug.print("[Asset] Flushing and releasing all assets\n", .{});

    // Clear all queues and free job-specific allocations
    for (pipelineio_queue.items) |job| {
        pipelineallocator.free(job.data.io.path);
    }
    pipelineio_queue.clearRetainingCapacity();

    for (pipelinedecode_queue.items) |job| {
        pipelineallocator.free(job.data.decode.bytes);
    }
    pipelinedecode_queue.clearRetainingCapacity();

    for (pipelineupload_queue.items) |job| {
        const loader = job.data.upload.loader;
        loader.destroy(job.data.upload.parsed, pipelineallocator);
    }
    pipelineupload_queue.clearRetainingCapacity();

    // Destroy all loaded asset payloads
    var it = registryentries.iterator();
    while (it.next()) |kv| {
        const entry = kv.value_ptr;
        if (entry.payload) |payload| {
            if (loadersgetLoaderById(kv.key_ptr.type_id)) |loader| {
                loader.destroy(payload, registryallocator);
            }
            entry.payload = null;
        }
    }

    // Note: registry.deinit() and pipeline.deinit() are called automatically
    // by Sparze's World.deinit() via the auto-deinit system
}

// Helper functions

fn readFile(allocator: std.mem.Allocator, asset_root: []const u8, path: []const u8) ![]u8 {
    // Build full path
    const full_path = try std.fs.path.join(allocator, &.{ asset_root, path });
    defer allocator.free(full_path);

    // Open and read file
    const file = try std.fs.cwd().openFile(full_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    if (bytes_read != file_size) {
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
    if (registrygetEntry(handle.id)) |entry| {
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
