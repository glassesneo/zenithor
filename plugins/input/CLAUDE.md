# Input Plugin

Mouse and keyboard input handling via Sokol events.

## Resources

**Mouse** (non-serializable)
- `x, y: f32` - Current position
- `dx, dy: f32` - Per-frame delta (reset each frame)
- `scroll_x, scroll_y: f32` - Scroll delta (reset each frame)
- `left_button, right_button, middle_button: bool` - Button states

**Keyboard** (non-serializable)
- `keys: ArrayBitSet(512)` - Key state bitset (64 bytes)
- `held_frame_map: EnumArray(Keycode, u32)` - Frames held per key
- `modifiers: u32` - Shift, Ctrl, Alt, Super bitmask
- `char_buffer: [32]u32` - UTF-32 character input (reset each frame)
- `char_count: usize` - Characters in buffer

### Keyboard Methods

```zig
fn isPressed(key: Keycode) bool  // True only on first press frame
fn isReleased(key: Keycode) bool // True only on release frame
fn isHeld(key: Keycode) bool     // True while held
fn heldFrames(key: Keycode) u32  // Frames held (0 if not held)
```

## Usage

```zig
const Input = @import("input_plugin");

fn playerControl(
    keyboard: Resource(Input.Keyboard),
    mouse: Resource(Input.Mouse),
    player: Query(struct { Position, Velocity })
) !void {
    const kb = keyboard.value;

    if (kb.isPressed(.W)) {
        // Jump on press
    }

    if (kb.isHeld(.SPACE)) {
        const frames = kb.heldFrames(.SPACE);
        // Charge power based on hold duration
    }

    if (mouse.value.left_button) {
        const target_x = mouse.value.x;
        const target_y = mouse.value.y;
        // Aim at mouse position
    }
}
```

## Implementation Notes

- Event handler updates resources from Sokol events
- Per-frame state (deltas, char buffer) reset in `.last` stage
- Frame counts incremented in `.last` stage (after user systems check)
- Use `isPressed()` for single-fire actions, `isHeld()` for continuous
