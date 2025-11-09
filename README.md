# Zenithor

A Zig-based, plugin-driven game engine framework using Sokol for graphics/windowing, Sparze for ECS, and Dear ImGui for UI. Supports both native and WebAssembly targets.

## Features

- **Plugin System**: Modular architecture with compile-time plugin composition
- **ECS Architecture**: Powered by Sparze ECS with efficient queries and groups
- **Cross-Platform**: Native builds and WebAssembly support
- **Graphics**: Sokol-based rendering with multiple backend options (OpenGL, OpenGL ES3, WebGPU)
- **UI**: Dear ImGui integration for immediate-mode GUI

## Quick Start

Build and run examples:

```bash
# Run tests
zig build test

# Build and run a native example
zig build run-demo_window

# Build for WebAssembly
zig build demo_2d -Dtarget=wasm32-emscripten

# Serve WebAssembly examples
zig build serve-examples -Dtarget=wasm32-emscripten
```

## Requirements

- Zig 0.15.1 or later

## Documentation

See [CLAUDE.md](CLAUDE.md) for detailed development documentation, plugin system guide, and API references.

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT License ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
