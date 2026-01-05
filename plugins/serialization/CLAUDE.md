# Serialization Plugin

Save/load game state to disk using Sparze serialization.

## Resources

**SaveFile**:
```zig
path: [256:0]u8      // File path buffer
len: usize           // Path length
timestamp: i128      // Last modification time
checksum_valid: bool // Set to true on successful save/load
```

Methods: `getPath()`, `getPathZ()`

## Systems

```zig
saveGame(commands, save_file: ResourceMut(SaveFile))   // Serialize world to file
loadGame(commands, save_file: ResourceMut(SaveFile))   // Deserialize world from file
```

## Usage

```zig
const zenithor = @import("zenithor");
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const Serialization = @import("serialization_plugin");
const InputPlugin = @import("input_plugin");

fn handleInput(keyboard: Resource(InputPlugin.Keyboard), save_file: ResourceMut(Serialization.SaveFile), commands: anytype) !void {
    if (keyboard.value.isPressed(.F5)) {
        try Serialization.saveGame(commands, save_file);
    }
    if (keyboard.value.isPressed(.F9)) {
        try Serialization.loadGame(commands, save_file);
    }
}
```

## Serialization Behavior

**Serialized**: Entities, components, resources, events (read buffer)
**Not serialized**: Command buffers, event write buffer, types with `pub const serialized = false`

Mark transient resources non-serializable:
```zig
pub const Time = struct {
    // ...
    pub const serialized = false;
};
```

## Build Requirements

**WASM**: Requires `-Dfilesystem` flag for IDBFS support
```bash
zig build serialization -Dtarget=wasm32-emscripten -Dfilesystem
```

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
- **@docs/WASM_DEVELOPMENT.md** - WASM filesystem configuration
- [Sparze Serialization](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) - Serializer API reference
