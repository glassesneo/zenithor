# WebAssembly Development

Guide for building and deploying Zenithor applications to WebAssembly.

## Quick Start

```bash
# Build WASM example
zig build rendering_2d -Dtarget=wasm32-emscripten

# Serve examples locally
zig build serve-examples -Dtarget=wasm32-emscripten

# With filesystem support (for serialization)
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem
```

Open browser to `http://localhost:8000`

## Build Options

### Target Platform

```bash
-Dtarget=wasm32-emscripten
```

Always use `wasm32-emscripten` for WASM builds. This target uses Emscripten toolchain for:
- Canvas/WebGL rendering
- Browser event handling
- File system emulation (IDBFS)

### Graphics Backend

```bash
# OpenGL (default)
zig build <example> -Dtarget=wasm32-emscripten -Dgl

# OpenGL ES3
zig build <example> -Dtarget=wasm32-emscripten -Dgles3

# WebGPU (experimental)
zig build <example> -Dtarget=wasm32-emscripten -Dwgpu
```

**Recommendation**: Use `-Dgl` (default) for maximum browser compatibility.

### Filesystem Support

```bash
-Dfilesystem
```

Enables Emscripten IDBFS (IndexedDB filesystem):
- Required for serialization plugin
- Persists data across browser sessions
- Increases binary size by ~50KB
- Async file operations

**Use when**: Your application needs to save/load game state.

### Stack Size

```bash
-Dstack-size=<MB>
```

Default: 5MB
Range: 1-16MB

Increase if you encounter stack overflow errors:

```bash
# Increase to 8MB
zig build showcase_3d -Dtarget=wasm32-emscripten -Dstack-size=8
```

**Symptoms of stack overflow**:
- "RuntimeError: memory access out of bounds"
- Crashes during deserialization
- Crashes with large recursive data structures

## Available Examples

All examples support WASM builds:

| Example | Description | WASM Command |
|---------|-------------|--------------|
| minimal_app | Basic window | `zig build minimal_app -Dtarget=wasm32-emscripten` |
| input_movement | Keyboard/mouse input | `zig build input_movement -Dtarget=wasm32-emscripten` |
| rendering_2d | 2D shapes | `zig build rendering_2d -Dtarget=wasm32-emscripten` |
| scene_3d | 3D rendering | `zig build scene_3d -Dtarget=wasm32-emscripten` |
| system_ordering | System execution order | `zig build system_ordering -Dtarget=wasm32-emscripten` |
| error_handling | Error recovery | `zig build error_handling -Dtarget=wasm32-emscripten` |
| serialization | Save/load state | `zig build serialization -Dtarget=wasm32-emscripten -Dfilesystem` |
| imgui_overlay | ImGui debug UI | `zig build imgui_overlay -Dtarget=wasm32-emscripten` |
| plugin_authoring | Plugin example | `zig build plugin_authoring -Dtarget=wasm32-emscripten` |
| showcase_3d | Complete 3D demo | `zig build showcase_3d -Dtarget=wasm32-emscripten` |

## Serving Examples

The build system includes a local development server:

```bash
# Serve all WASM examples
zig build serve-examples -Dtarget=wasm32-emscripten

# With filesystem support
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem
```

**Server configuration**:
- Port: 8000
- Root: `zig-out/web/`
- Auto-shutdown: Ctrl+C

**File structure**:
```
zig-out/web/
├── index.html              (example list)
├── minimal_app.html
├── minimal_app.js
├── minimal_app.wasm
├── rendering_2d.html
├── rendering_2d.js
├── rendering_2d.wasm
└── ...
```

## WASM-Specific Considerations

### Memory Management

WASM has stricter memory constraints than native:

1. **Rely on Zenithor's AppState strategy**
   - Zenithor uses an arena for the application's lifetime.
   - On WASM, `AppState` is heap-allocated to avoid dangling pointers because `sokol.app.run()` returns immediately in the browser event model.
   - Base allocator is `std.heap.c_allocator` on WASM.

2. **Avoid Large Stack Allocations**
   ```zig
   // Bad: Large stack array
   var buffer: [1024 * 1024]u8 = undefined;

   // Good: Heap allocation
   var buffer = try allocator.alloc(u8, 1024 * 1024);
   defer allocator.free(buffer);
   ```

3. **Graphics Plugin Memory**
   - 3D rendering uses heap-allocated staging buffers (~3.6MB)
   - Allocated once at startup, reused every frame
   - No per-frame allocation overhead

### Input Handling

WASM input events are processed via Sokol:

```zig
const InputPlugin = @import("input_plugin");

fn handleEvent(event: sokol.app.Event, world: anytype) !void {
    // Mouse and keyboard events work identically to native
    const mouse: *InputPlugin.Mouse = world.getResourcePtrMut(InputPlugin.Mouse);
    const keyboard: *InputPlugin.Keyboard = world.getResourcePtrMut(InputPlugin.Keyboard);

    // Browser-specific: Handle visibility changes
    if (event.type == .SUSPENDED) {
        // Page lost focus, pause game
    }
    if (event.type == .RESUMED) {
        // Page gained focus, resume game
    }
}
```

**Browser gotchas**:
- No raw mouse input (pointer lock available)
- No access to certain keys (F11, Ctrl+W, etc.)
- Touch events mapped to mouse

### File System

When `-Dfilesystem` is enabled:

```zig
const Serialization = @import("serialization_plugin");

fn saveGame(commands: anytype, save_file: ResourceMut(Serialization.SaveFile)) !void {
    // Writes to IDBFS (IndexedDB)
    try Serialization.saveGame(commands, save_file);

    // Data persists across browser sessions
    // Stored in: IndexedDB > "/" > "savegame.spze"
}
```

**IDBFS caveats**:
- Async operations (may have frame delay)
- Storage quota limits (typically 50MB+)
- Not accessible outside browser
- Can be cleared by user

### Performance

WASM performance tips:

1. **Use Release Builds**
   ```bash
   zig build <example> -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast
   ```

2. **Enable WASM SIMD** (where supported)
   - Automatically enabled by Zig for wasm32-emscripten
   - Requires modern browsers (Chrome 91+, Firefox 89+)

3. **Minimize Draw Calls**
   - Graphics plugin batches 2D/3D shapes
   - Use fewer, larger meshes vs many small ones

4. **Avoid Blocking Operations**
   - File I/O is async
   - Long computations may freeze browser tab

### Debugging

**Browser Console**:
- Zig `std.debug.print()` → browser console
- Errors and panics logged to console

**Chrome DevTools**:
```
F12 → Console (for logs)
F12 → Memory (for heap snapshots)
F12 → Performance (for profiling)
```

**WASM Stack Traces**:
Enable debug info:
```bash
zig build <example> -Dtarget=wasm32-emscripten -Doptimize=Debug
```

Browser shows function names in stack traces.

## Deployment

### Production Build

```bash
# Optimized release build
zig build <example> -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall

# With filesystem support
zig build <example> -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall -Dfilesystem
```

**Build artifacts** (in `zig-out/web/`):
- `<example>.html` - HTML page
- `<example>.js` - Emscripten loader
- `<example>.wasm` - WASM binary

### Hosting

Deploy to any static hosting service:

**GitHub Pages**:
```bash
cp -r zig-out/web/* docs/
git add docs/
git commit -m "Deploy WASM build"
git push
```

Enable Pages in repo settings → Source: `docs/` folder.

**Netlify / Vercel**:
- Drag-and-drop `zig-out/web/` folder
- Or configure build command: `zig build serve-examples -Dtarget=wasm32-emscripten`

**S3 / CloudFront**:
```bash
aws s3 sync zig-out/web/ s3://my-bucket/
```

**MIME types**: Ensure server sends correct headers:
```
.wasm → application/wasm
.js   → application/javascript
.html → text/html
```

## Troubleshooting

### "RuntimeError: memory access out of bounds"

**Cause**: Stack overflow or heap corruption

**Solutions**:
1. Increase stack size: `-Dstack-size=8`
2. Move large allocations to heap
3. Check for buffer overruns

### "Failed to fetch .wasm"

**Cause**: CORS policy or incorrect path

**Solutions**:
1. Serve via `zig build serve-examples` (no CORS issues)
2. Use `python -m http.server` in `zig-out/web/`
3. Check browser console for exact error

### Serialization not working

**Cause**: Missing `-Dfilesystem` flag

**Solution**:
```bash
zig build serialization -Dtarget=wasm32-emscripten -Dfilesystem
```

### Black screen / Nothing renders

**Checks**:
1. Browser console for errors
2. Canvas element created (`<canvas id="canvas"></canvas>`)
3. WebGL supported (`about:gpu` in Chrome)
4. Graphics backend matches browser capabilities

### Performance issues

**Checks**:
1. Use `ReleaseSmall` or `ReleaseFast` optimize mode
2. Check browser profiler for hot spots
3. Reduce draw calls (fewer entities with shapes)
4. Disable ImGui overlays in production

## Platform Differences

| Feature | Native | WASM |
|---------|--------|------|
| File I/O | Synchronous | Async (IDBFS) |
| Stack size | Large (MB) | Limited (configurable) |
| Allocator | page_allocator | c_allocator |
| Input | Full keyboard | Browser-limited |
| Graphics | All backends | GL, GLES3, WebGPU |
| Debugging | GDB/LLDB | Browser DevTools |
| Performance | ~100% | ~70-90% |

## Browser Compatibility

**Minimum requirements**:
- Chrome 57+ / Edge 79+
- Firefox 52+
- Safari 11+

**Recommended**:
- Chrome 91+ (WASM SIMD)
- Firefox 89+ (WASM SIMD)
- Safari 15+ (Better WebGL2 support)

**WebGPU** (experimental):
- Chrome 113+
- Edge 113+
- Firefox behind flag
- Safari Technology Preview

## See Also

- [Emscripten Documentation](https://emscripten.org/docs/)
- [WebAssembly Specification](https://webassembly.github.io/spec/)
- [Sokol WASM Guide](https://github.com/floooh/sokol/blob/master/README.md#webassembly)
- build.zig - Build configuration
- examples/ - WASM-compatible examples
