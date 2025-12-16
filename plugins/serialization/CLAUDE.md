# Serialization Plugin

Save/load game state to disk using Sparze serialization.

## Resources

**SaveFile**
- `path: [256:0]u8` - File path buffer
- `len: usize` - Path length
- `timestamp: i128` - Last modification time
- `checksum_valid: bool` - CRC32 validation flag

Methods:
- `getPath() []const u8` - Get path slice
- `getPathZ() [:0]const u8` - Get null-terminated path

## Systems

**saveGame(commands, save_file: Resource(SaveFile))**
- Serializes world to file via `commands.serializeToFile()`
- Updates SaveFile metadata (timestamp, checksum)

**loadGame(commands, save_file: Resource(SaveFile))**
- Deserializes world from file via `commands.deserializeFromFile()`
- Updates SaveFile metadata

## Usage

```zig
const Serialization = @import("serialization_plugin");

fn handleInput(
    keyboard: Resource(Keyboard),
    save_file: Resource(Serialization.SaveFile),
    commands: anytype
) !void {
    if (keyboard.value.isPressed(.F5)) {
        try Serialization.saveGame(commands, save_file);
    }

    if (keyboard.value.isPressed(.F9)) {
        try Serialization.loadGame(commands, save_file);
    }
}
```

## Serialization Behavior

Inherited from Sparze (see sparze CLAUDE.md):
- **Serialized**: Entities, components, resources, events (read buffer)
- **Not serialized**: command buffers, event write buffer, types with `pub const serialized = false`
- **POD types**: Auto-serialized
- **Non-POD**: Require custom `Serializer` with `serialize()`/`deserialize()` methods

## Notes

- Default save path: `"savegame.spze"`
- File format includes type hash, CRC32, version for safety
- Mark transient resources with `pub const serialized = false` (Time, Input, etc.)
- WASM requires `-Dfilesystem` build flag for IDBFS support
