# Zenithor

A 2D/3D Application Framework for Zig, backed by Sokol and Sparze ECS. Native and WebAssembly targets with compile-time plugin architecture.

## Highlights

- **Compile-time plugins**: Tuple-based plugin registration with automatic dependency expansion and builtin Transform/Rotation/Scale/Color.
- **Zero-cost ECS**: [Sparze](https://github.com/glassesneo/sparze) provides queries, groups, and events with deterministic system scheduling.
- **Cross-platform**: Sokol backends for OpenGL, OpenGL ES3, and WebGPU.
- **Minimal batteries included**: Shapes2D, Shapes3D, Time, Input, ImGui, Asset, and Serialization plugins ready to drop in.
- **Error-tolerant loop**: System and event handler failures become events instead of crashes (see `src/core/CLAUDE.md`).

## Quick Start

```bash
# Run tests
zig build test

# Native examples
zig build run-minimal_app       # Minimal app + plugin wiring
zig build run-rendering_2d      # 2D rendering + layering
zig build run-scene_3d          # 3D scene basics

# WebAssembly build + local server
zig build rendering_2d -Dtarget=wasm32-emscripten
zig build serve-examples -Dtarget=wasm32-emscripten       # serve all WASM demos
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem  # with IDBFS for serialization

# Graphics backend override (default: -Dgl)
zig build <target> -Dgl | -Dgles3 | -Dwgpu
```

Minimal app:

```zig
const zenithor = @import("zenithor");
const Shapes2DPlugin = @import("shapes2d_plugin");
const Time = @import("time_plugin");
const Input = @import("input_plugin");

pub fn main() void {
    zenithor.run(.{ Shapes2DPlugin, Time, Input }, .{
        .window_config = .{
            .width = 1280,
            .height = 800,
            .title = "Zenithor",
            .fullscreen = false,
            .high_dpi = true,
        },
    });
}
```

## Examples

All examples are in `examples/` and can be built with `zig build <name>` or run with `zig build run-<name>`:

- **minimal_app**: Minimal app + plugin wiring
- **input_movement**: Input + time driven movement
- **rendering_2d**: 2D rendering + layering
- **scene_3d**: 3D scene basics
- **custom_shader_3d**: Custom rim/Fresnel shader flow
- **system_ordering**: System staging and ordering
- **error_handling**: Event flow and error handling
- **serialization**: Serialization round-trip
- **imgui_overlay**: ImGui debug overlay
- **sprite_rendering**: Sprite rendering with textures
- **plugin_authoring**: Plugin authoring + Requires
- **showcase_3d**: Comprehensive 3D showcase (demonstrates all features)

## Plugin Catalog

- **Shapes2D**: 2D Point/Line/Triangle/Rectangle/Circle rendering via Sokol GL.
- **Shapes3D**: 3D Box/Sphere/Cylinder/Torus/Plane rendering with Blinn-Phong, PBR, and unlit shaders; optional Material component; Camera3D and Light3D resources.
- **Time**: DeltaTime resource, FPS tracking.
- **Input**: Mouse and Keyboard resources, event handlers.
- **ImGui**: Dear ImGui frame setup/render submit, docking optional.
- **Asset**: Asset loading, caching, and lifecycle management for textures.
- **Sprite**: ECS-integrated 2D textured sprite rendering with sprite sheets and Z-depth ordering.
- **Serialization**: Save/load game state, WASM filesystem support via `-Dfilesystem`.
- **Builtin**: Transform, Rotation, Scale, and Color components always included.

## Documentation

Comprehensive documentation with AI-first design for discoverability:

- **[docs/PLUGIN_DEVELOPMENT.md](docs/PLUGIN_DEVELOPMENT.md)** - Step-by-step guide for creating plugins
- **[docs/SYSTEM_ORDERING.md](docs/SYSTEM_ORDERING.md)** - System execution order, priority, and constraints
- **[docs/APPLICATION_LIFECYCLE.md](docs/APPLICATION_LIFECYCLE.md)** - Internal flow of `zenithor.run()`
- **[docs/WASM_DEVELOPMENT.md](docs/WASM_DEVELOPMENT.md)** - WebAssembly builds and deployment
- **[CLAUDE.md](CLAUDE.md)** - Quick reference (commands, constraints, links)
- **[src/core/CLAUDE.md](src/core/CLAUDE.md)** - Core engine internals
- **Plugin docs**: Most plugins have a `CLAUDE.md` for quick reference

The codebase also includes extensive DocComments on public APIs with ubiquitous language tags for AI agent discoverability.

## Directory Layout

```
src/root.zig            # Public API exports (with comprehensive DocComments)
src/core/               # Engine core (application, builtin, scheduler)
plugins/                # Standard plugins (renderer, shapes2d, shapes3d, time, input, imgui, asset, sprite, serialization)
examples/               # Example programs
docs/                   # Detailed documentation
build.zig               # Build graph and plugin module wiring
```

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT License ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
