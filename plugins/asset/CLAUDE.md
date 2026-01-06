# Asset Plugin

Asynchronous asset loading with multi-stage pipeline (IO→Decode→Upload).

## Resources

- **AssetRegistry** - Central registry storing asset states, payloads, and refcounts
- **LoaderRegistry** - Type-to-loader VTable mapping
- **JobPipeline** - Priority queues for IO/decode/upload stages with per-frame budgets
- **IoConfig** - Asset root path and per-stage time budgets (microseconds)
- **AssetStats** - Cache hits/misses, loading/ready counts
- **EmbeddedAssets** - Compile-time embedded asset data

## Events

- **AssetRequest** - Request asset load (type_id, path, source, priority)
- **AssetLoaded** - Asset ready (handle, type_id)
- **AssetFailed** - Load failed (handle, error_kind, retry_count)
- **AssetReload** / **AssetDependencyChanged** / **AssetEvicted** - Hot reload and cache management

## Core Types

```zig
const asset = @import("asset_plugin");

// Handle-based access (versioned to prevent use-after-free)
const handle = try registry.createHandle(Texture, asset.AssetLocator.filesystem("player.png"));
// Or for embedded: asset.AssetLocator.embedded("player.png")

// Check state
if (registry.validateHandle(handle.handle)) |entry| {
    if (entry.state == .ready) {
        const texture: *Texture = @ptrCast(@alignCast(entry.payload));
    }
}
```

## Custom Loaders

```zig
const MyLoader = struct {
    pub const AssetType = MyAsset;
    pub fn canLoad(path: []const u8) bool { return std.mem.endsWith(u8, path, ".my"); }
    pub fn load(bytes: []const u8, allocator: Allocator) !*MyAsset { ... }
    pub fn destroy(asset: *MyAsset, allocator: Allocator) void { ... }
    // Optional: reload(), getMemoryUsage()
};

// Register in startup system
loader_registry.registerLoader(MyAsset, asset.makeLoaderVTable(MyLoader));
```

## Implementation

- **startup/.first** (priority -100): Registers built-in loaders (texture)
- **main/.first** (priority -50): `pumpIoJobs` - processes requests, reads files/embedded
- **main/.pre_update** (priority -50): `pumpDecodeJobs` - parses asset data
- **main/.pre_render** (priority -100): `pumpUploadJobs` - finalizes, emits AssetLoaded
- **terminate/.last** (priority -100): Flushes queues and destroys payloads (before sokol.gfx shutdown)

## Asset Sources

- **AssetSource.filesystem** - Load from disk (blocked on WASM)
- **AssetSource.embedded** - Load from compile-time embedded data

AssetId includes source in hash to prevent collisions between embedded and filesystem assets with the same path.
