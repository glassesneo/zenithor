const std = @import("std");

// Re-export public API
pub const registry = @import("registry.zig");
pub const loader = @import("loader.zig");
pub const events = @import("events.zig");
pub const config = @import("config.zig");

// Core types
pub const AssetId = registry.AssetId;
pub const AssetHandle = registry.AssetHandle;
pub const TypedHandle = registry.TypedHandle;
pub const AssetState = registry.AssetState;
pub const AssetRegistry = registry.AssetRegistry;

// Loader types
pub const LoaderVTable = loader.LoaderVTable;
pub const LoaderRegistry = loader.LoaderRegistry;
pub const JobPipeline = loader.JobPipeline;
pub const LoadContext = loader.LoadContext;
pub const makeLoaderVTable = loader.makeLoaderVTable;

// Events
pub const AssetRequest = events.AssetRequest;
pub const AssetLoaded = events.AssetLoaded;
pub const AssetFailed = events.AssetFailed;
pub const AssetReload = events.AssetReload;
pub const AssetDependencyChanged = events.AssetDependencyChanged;
pub const AssetEvicted = events.AssetEvicted;

// Config
pub const IoConfig = config.IoConfig;
pub const AssetStats = config.AssetStats;
pub const CachePolicy = config.CachePolicy;
pub const EmbeddedAssets = config.EmbeddedAssets;
pub const AssetSource = config.AssetSource;
pub const AssetLocator = config.AssetLocator;

// Import systems
const systems_module = @import("systems.zig");

// Import and re-export texture loader for convenience
pub const texture_loader = @import("loaders/texture.zig");
pub const Texture = texture_loader.Texture;

// Plugin declarations
pub const Components = .{};

pub const Resources = .{
    AssetRegistry,
    LoaderRegistry,
    JobPipeline,
    IoConfig,
    AssetStats,
    EmbeddedAssets,
};

pub const Events = .{
    AssetRequest,
    AssetLoaded,
    AssetFailed,
    AssetReload,
    AssetDependencyChanged,
    AssetEvicted,
};

pub const Groups = .{};

// No plugin dependencies for now
pub const Requires = .{};

// System declarations
pub const systems = .{
    .startup = &.{
        .{ .system = systems_module.initRegistry, .stage = .first, .config = .{
            .priority = -100,
            .tags = &.{"asset-init"},
        } },
    },
    .main = &.{
        // IO jobs run first in the frame
        .{ .system = systems_module.pumpIoJobs, .stage = .first, .config = .{
            .priority = -50,
            .tags = &.{"asset-io"},
        } },
        // Decode jobs run in pre_update (after first stage completes)
        .{ .system = systems_module.pumpDecodeJobs, .stage = .pre_update, .config = .{
            .priority = -50,
            .tags = &.{"asset-decode"},
        } },
        // Upload jobs run in pre_render (after pre_update stage completes)
        .{ .system = systems_module.pumpUploadJobs, .stage = .pre_render, .config = .{
            .priority = -100,
            .tags = &.{"asset-upload"},
        } },
    },
    .terminate = &.{
        // Run BEFORE render_context's shutdownGraphics (priority 0)
        // so GPU resources can be destroyed while sokol.gfx is still valid
        .{ .system = systems_module.flushAndRelease, .stage = .last, .config = .{
            .priority = -100,
        } },
    },
};
