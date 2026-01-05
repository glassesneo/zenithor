const registry = @import("registry.zig");

pub const AssetHandle = registry.AssetHandle;
pub const AssetErrorKind = registry.AssetErrorKind;
pub const EvictionReason = registry.EvictionReason;
pub const AssetId = registry.AssetId;

/// Request to load an asset
pub const AssetRequest = struct {
    type_id: u32,
    path: []const u8,
    priority: u8 = 128,
    requester: u32, // Entity ID for tracking

    /// Non-serializable (transient event)
    pub const serialized = false;
};

/// Asset successfully loaded
pub const AssetLoaded = struct {
    handle: AssetHandle,
    type_id: u32,

    /// Non-serializable (transient event)
    pub const serialized = false;
};

/// Asset loading failed
pub const AssetFailed = struct {
    handle: AssetHandle,
    error_kind: AssetErrorKind,
    retry_count: u8,
    fallback_used: bool,

    /// Non-serializable (transient event)
    pub const serialized = false;
};

/// Asset reload request (hot reload)
pub const AssetReload = struct {
    path: []const u8,
    content_hash: u64, // Detect actual changes

    /// Non-serializable (transient event)
    pub const serialized = false;
};

/// Asset dependency changed (triggers cascading reload)
pub const AssetDependencyChanged = struct {
    asset_id: AssetId,
    old_version: u32,
    new_version: u32,

    /// Non-serializable (transient event)
    pub const serialized = false;
};

/// Asset evicted from cache
pub const AssetEvicted = struct {
    handle: AssetHandle,
    reason: EvictionReason,

    /// Non-serializable (transient event)
    pub const serialized = false;
};
