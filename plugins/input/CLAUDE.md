# Input Plugin

Mouse and keyboard input handling via Sokol events.

## Resources

**Mouse** (non-serializable):
- `x, y: f32` - Current position
- `dx, dy: f32` - Frame delta (reset each frame)
- `scroll_x, scroll_y: f32` - Scroll delta (reset each frame)
- `left_button, right_button, middle_button: bool` - Button states
- Methods: `isPressed()`, `isReleased()`, `isHeld()`, `heldFrames()`

**Keyboard** (non-serializable):
- `keys: ArrayBitSet(512)` - Key states (64 bytes)
- `modifiers: u32` - Shift, Ctrl, Alt, Super bitmask
- `char_buffer: [32]u32` - UTF-32 input (reset each frame)
- Methods: `isPressed()`, `isReleased()`, `isHeld()`, `heldFrames()`

## Usage

```zig
const zenithor = @import("zenithor");
const Resource = zenithor.Resource;
const Input = @import("input_plugin");

fn playerControl(keyboard: Resource(Input.Keyboard), mouse: Resource(Input.Mouse)) !void {
    if (keyboard.value.isPressed(.W)) {
        // Jump on press
    }
    if (keyboard.value.isHeld(.SPACE)) {
        const frames = keyboard.value.heldFrames(.SPACE);
        // Charge power based on hold duration
    }
    if (mouse.value.isPressed(.LEFT)) {
        // Fire on click at mouse.value.x, mouse.value.y
    }
}
```

## Implementation

- Event handler updates from Sokol events
- Per-frame state (deltas, char buffer) reset in `.last` stage
- Frame counts incremented in `.last` stage
- Use `isPressed()` for single-fire, `isHeld()` for continuous, `isReleased()` for release detection

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
