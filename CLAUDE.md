# Zenithor

Plugin-driven 2D/3D Application Framework for Zig using Sokol, Sparze (ECS), and Dear ImGui.

## Quick Start

```bash
zig build test                        # Run tests
zig build run-minimal_app             # Run native example
zig build serve-examples -Dtarget=wasm32-emscripten  # WASM examples
```

**Examples**: minimal_app, input_movement, rendering_2d, scene_3d, system_ordering, error_handling, serialization, imgui_overlay, sprite_rendering, plugin_authoring, showcase_3d

## Critical Constraints

**IMPORTANT**: Core manages the application loop and plugin orchestration. All Sokol subsystems are initialized by plugins: `render_context` plugin initializes graphics (`sokol.gfx` and `sokol.gl`), `time_plugin` initializes timing (`sokol.time`), and other subsystem plugins initialize their own modules (e.g. `imgui_plugin` initializes `sokol.imgui`). Plugins should not duplicate these initializations.

**IMPORTANT**: World construction uses tuple VALUES: `sparze.World(.{Comp}, .{Res}, .{Events}, .{Groups})`

**IMPORTANT**: Zig 0.15.1+ required

**IMPORTANT**: For allocator usage in systems, request `allocator: std.mem.Allocator` as a system parameter. Sparze injects the world allocator which is already platform-aware (WASM uses `c_allocator`, native uses `page_allocator` or user-specified). Never use `builtin.target.cpu.arch.isWasm()` checks to pick allocators manually. See @docs/PLUGIN_DEVELOPMENT.md for details.

## Common Commands

```bash
# Native builds
zig build <example>                   # Build example
zig build run-<example>               # Run example

# WASM builds
zig build <example> -Dtarget=wasm32-emscripten
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem  # With save/load

# Graphics backends
zig build <example> -Dgl              # OpenGL (default)
zig build <example> -Dgles3           # OpenGL ES3
zig build <example> -Dwgpu            # WebGPU
```

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Step-by-step plugin creation guide
- **@docs/SYSTEM_ORDERING.md** - System execution order and constraints
- **@docs/APPLICATION_LIFECYCLE.md** - Internal flow of zenithor.run()
- **@docs/WASM_DEVELOPMENT.md** - WebAssembly builds and deployment
- **@src/core/CLAUDE.md** - Core engine internals
- [Sparze](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) - ECS framework reference
