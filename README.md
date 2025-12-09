# Zenithor

A 2D/3D "Game Engine Framework" for Zig, backed by Sokol and Sparze ECS. Native and WebAssembly targets with compile-time plugin architecture.

## Highlights

- **Compile-time plugins**: Tuple-based plugin registration with automatic dependency expansion and builtin Transform/Color.
- **Zero-cost ECS**: [Sparze](https://github.com/glassesneo/sparze) provides queries, groups, and events with deterministic system scheduling.
- **Cross-platform**: Sokol backends for OpenGL, OpenGL ES3, and WebGPU.
- **Minimal batteries included**: Graphics, Time, Input, ImGui, and Serialization plugins ready to drop in.
- **Error-tolerant loop**: System and event handler failures become events instead of crashes (see `src/core/CLAUDE.md`).

## Quick Start

```bash
# Run tests
zig build test

# Native example (window, input, rendering)
zig build run-demo_window

# Other native demos
zig build run-demo_2d
zig build run-demo_imgui

# WebAssembly build + local server
zig build demo_2d -Dtarget=wasm32-emscripten
zig build serve-examples -Dtarget=wasm32-emscripten       # serve all WASM demos
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem  # with IDBFS for serialization

# Graphics backend override (default: -Dgl)
zig build <target> -Dgl | -Dgles3 | -Dwgpu
```

Minimal app:

```zig
const zenithor = @import("zenithor");
const Graphics = @import("graphics_plugin");
const Time = @import("time_plugin");
const Input = @import("input_plugin");

pub fn main() void {
    zenithor.run(.{ Graphics, Time, Input }, .{});
}
```

## Plugin Catalog

- **Graphics**: 2D Point/Line/Triangle/Rectangle/Circle rendering via Sokol GL; 3D Box/Sphere/Cylinder/Torus/Plane rendering with Blinn-Phong, PBR, and unlit shaders; optional Color and Material components; Camera3D and Light3D resources.
- **Time**: DeltaTime resource, FPS tracking.
- **Input**: Mouse and Keyboard resources, event handlers.
- **ImGui**: Dear ImGui frame setup/render submit, docking optional.
- **Serialization**: Save/load game state, WASM filesystem support via `-Dfilesystem`.
- **Builtin**: Transform and Color components always included.

## Directory Layout

```
src/root.zig            # Public API exports
src/core/               # Engine core (application, builtin, scheduler)
plugins/                # Standard plugins (graphics, time, input, imgui, serialization)
examples/               # Example programs
build.zig               # Build graph and plugin module wiring
```

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT License ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
