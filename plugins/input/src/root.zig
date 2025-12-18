const std = @import("std");
const sparze = @import("sparze");
const sokol = @import("sokol");

const zenithor = @import("zenithor");
const Stage = zenithor.Stage;

/// Mouse input resource containing mouse position, deltas, scroll, and button states.
///
/// **Ubiquitous Language**: Input Snapshot, Per-Frame Deltas, Held Frames
///
/// Updated from Sokol events by the input plugin's event handler. State is reset/updated
/// in `.last` stage cleanup system.
///
/// **Critical specifications**:
/// - `x, y`: Mouse position in **window pixels** (coordinate space per Sokol: origin at top-left)
/// - `dx, dy, scroll_x, scroll_y`: **Reset to 0 each frame** in `.last` stage
/// - `held_frame_map`: Incremented in `.last` stage for held buttons
/// - `isPressed()`: True when `held_frame_map == 1` (first frame only)
/// - `isReleased()`: True on the frame a button is released
/// - `isHeld()`: True while button is down
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md
pub const Mouse = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    dx: f32 = 0.0, // Per-frame mouse delta X
    dy: f32 = 0.0, // Per-frame mouse delta Y
    scroll_x: f32 = 0.0, // Per-frame scroll X
    scroll_y: f32 = 0.0, // Per-frame scroll Y
    left_button: bool = false,
    right_button: bool = false,
    middle_button: bool = false,
    held_frame_map: std.EnumArray(sokol.app.Mousebutton, u32) = .initFill(0), // Tracks frames each button has been held

    /// Returns true only on the frame the button was first pressed
    pub fn isPressed(self: *const Mouse, button: sokol.app.Mousebutton) bool {
        return self.held_frame_map.get(button) == 1;
    }

    /// Returns true only on the frame the button was released
    pub fn isReleased(self: *const Mouse, button: sokol.app.Mousebutton) bool {
        // Released means: was held (frame count > 0), but not held anymore
        const was_held = self.held_frame_map.get(button) > 0;
        const is_held = switch (button) {
            .LEFT => self.left_button,
            .RIGHT => self.right_button,
            .MIDDLE => self.middle_button,
            else => false,
        };
        return was_held and !is_held;
    }

    /// Returns true while the button is held down
    pub fn isHeld(self: *const Mouse, button: sokol.app.Mousebutton) bool {
        return switch (button) {
            .LEFT => self.left_button,
            .RIGHT => self.right_button,
            .MIDDLE => self.middle_button,
            else => false,
        };
    }

    /// Returns number of frames the button has been held (0 if not held)
    pub fn heldFrames(self: *const Mouse, button: sokol.app.Mousebutton) u32 {
        return self.held_frame_map.get(button);
    }

    pub const serialized = false;
};

/// Keyboard input resource containing key states and modifiers.
///
/// **Ubiquitous Language**: Input Snapshot, Key State, Text Input Buffer, Held Frames
///
/// Updated from Sokol events by the input plugin's event handler. State is reset/updated
/// in `.last` stage cleanup system.
///
/// **Critical specifications**:
/// - `keys`: BitSet for key states, bounds [0, 511] (512 keys max)
/// - `char_buffer`: UTF-32 text input, **cleared each frame** in `.last` stage (max 32 chars/frame)
/// - `modifiers`: Bitmask for Shift, Ctrl, Alt, Super (platform-specific)
/// - `held_frame_map`: Incremented in `.last` stage for held keys
/// - `isPressed()`: True when `held_frame_map == 1` (first frame only)
/// - `isReleased()`: True on the frame a key is released
/// - `isHeld()`: True while key is down
///
/// **Text input vs key state**: Use `char_buffer` for text input, `keys`/`isPressed()` for gameplay bindings.
///
/// **See Also**: docs/APPLICATION_LIFECYCLE.md
pub const Keyboard = struct {
    keys: std.bit_set.ArrayBitSet(usize, 512) = .initEmpty(), // Key states as bit set (64 bytes)
    held_frame_map: std.EnumArray(sokol.app.Keycode, u32) = .initFill(0), // Tracks frames each key has been held
    modifiers: u32 = 0, // Modifier key bitmask (Shift, Ctrl, Alt, Super)
    char_buffer: [32]u32 = undefined, // UTF-32 character input buffer
    char_count: usize = 0, // Number of characters in buffer this frame

    /// Returns true only on the frame the key was first pressed
    pub fn isPressed(self: *const Keyboard, key: sokol.app.Keycode) bool {
        return self.held_frame_map.get(key) == 1;
    }

    /// Returns true only on the frame the key was released
    pub fn isReleased(self: *const Keyboard, key: sokol.app.Keycode) bool {
        const key_code: i32 = @intFromEnum(key);
        if (key_code < 0 or 512 <= key_code) return false;

        // Released means: was held (frame count > 0), but not in bitset anymore
        const was_held = self.held_frame_map.get(key) > 0;
        const is_held = self.keys.isSet(@intCast(key_code));
        return was_held and !is_held;
    }

    /// Returns true while the key is held down
    pub fn isHeld(self: *const Keyboard, key: sokol.app.Keycode) bool {
        const key_code: i32 = @intFromEnum(key);
        if (key_code < 0 or key_code >= 512) return false;
        return self.keys.isSet(@intCast(key_code));
    }

    /// Returns number of frames the key has been held (0 if not held)
    pub fn heldFrames(self: *const Keyboard, key: sokol.app.Keycode) u32 {
        return self.held_frame_map.get(key);
    }

    fn incrementHeldKeyFrames(self: *Keyboard) void {
        var iter = self.keys.iterator(.{});
        while (iter.next()) |index| {
            const key: sokol.app.Keycode = @enumFromInt(index);
            self.held_frame_map.getPtr(key).* += 1;
        }
    }

    fn cleanupReleasedKeys(self: *Keyboard) void {
        inline for (@typeInfo(sokol.app.Keycode).@"enum".fields) |key_field| {
            const key: sokol.app.Keycode = @enumFromInt(key_field.value);
            if (!self.isHeld(key) and self.held_frame_map.get(key) > 0) {
                self.held_frame_map.set(key, 0);
            }
        }
    }

    pub const serialized = false;
};

pub const Components = .{};
pub const Resources = .{
    Mouse,
    Keyboard,
};

pub const Events = .{};

/// Sokol event mapping to input state.
///
/// Updates Mouse/Keyboard resources from browser/native input events.
/// Frame counters (held frames) incremented in `.last` stage cleanup system.
fn handleEvent(event: sokol.app.Event, world: anytype) void {
    const mouse: *Mouse = world.getResourcePtrMut(Mouse);
    const keyboard: *Keyboard = world.getResourcePtrMut(Keyboard);

    switch (event.type) {
        .MOUSE_MOVE => {
            mouse.x = event.mouse_x;
            mouse.y = event.mouse_y;
            mouse.dx = event.mouse_dx;
            mouse.dy = event.mouse_dy;
        },
        .MOUSE_DOWN => {
            switch (event.mouse_button) {
                .LEFT => {
                    mouse.left_button = true;
                    mouse.held_frame_map.set(.LEFT, 1);
                },
                .RIGHT => {
                    mouse.right_button = true;
                    mouse.held_frame_map.set(.RIGHT, 1);
                },
                .MIDDLE => {
                    mouse.middle_button = true;
                    mouse.held_frame_map.set(.MIDDLE, 1);
                },
                else => {},
            }
        },
        .MOUSE_UP => {
            switch (event.mouse_button) {
                .LEFT => mouse.left_button = false,
                .RIGHT => mouse.right_button = false,
                .MIDDLE => mouse.middle_button = false,
                else => {},
            }
        },
        .MOUSE_SCROLL => {
            mouse.scroll_x = event.scroll_x;
            mouse.scroll_y = event.scroll_y;
        },
        .KEY_DOWN => {
            const key_code: i32 = @intFromEnum(event.key_code);
            if (key_code >= 0 and key_code < 512) {
                keyboard.keys.set(@intCast(key_code));
                // Set to 1 on first press (updateFrameCounts will increment)
                keyboard.held_frame_map.set(event.key_code, 1);
            }
            keyboard.modifiers = event.modifiers;
        },
        .KEY_UP => {
            const key_code: i32 = @intFromEnum(event.key_code);
            if (key_code >= 0 and key_code < 512) {
                keyboard.keys.unset(@intCast(key_code));
            }
            keyboard.modifiers = event.modifiers;
        },
        .CHAR => {
            if (keyboard.char_count < keyboard.char_buffer.len) {
                keyboard.char_buffer[keyboard.char_count] = event.char_code;
                keyboard.char_count += 1;
            }
        },
        else => {},
    }
}

fn resetPerFrameState(mouse: sparze.ResourceMut(Mouse), keyboard: sparze.ResourceMut(Keyboard)) void {
    // Reset per-frame deltas and buffers
    mouse.value.dx = 0.0;
    mouse.value.dy = 0.0;
    mouse.value.scroll_x = 0.0;
    mouse.value.scroll_y = 0.0;
    keyboard.value.char_count = 0;
}

fn updateFrameCounts(mouse: sparze.ResourceMut(Mouse), keyboard: sparze.ResourceMut(Keyboard)) void {
    keyboard.value.incrementHeldKeyFrames();
    keyboard.value.cleanupReleasedKeys();

    // Increment frame count for all held mouse buttons
    if (mouse.value.left_button) {
        mouse.value.held_frame_map.getPtr(.LEFT).* += 1;
    } else if (mouse.value.held_frame_map.get(.LEFT) > 0) {
        // Clean up released button
        mouse.value.held_frame_map.set(.LEFT, 0);
    }

    if (mouse.value.right_button) {
        mouse.value.held_frame_map.getPtr(.RIGHT).* += 1;
    } else if (mouse.value.held_frame_map.get(.RIGHT) > 0) {
        mouse.value.held_frame_map.set(.RIGHT, 0);
    }

    if (mouse.value.middle_button) {
        mouse.value.held_frame_map.getPtr(.MIDDLE).* += 1;
    } else if (mouse.value.held_frame_map.get(.MIDDLE) > 0) {
        mouse.value.held_frame_map.set(.MIDDLE, 0);
    }
}

fn init(commands: anytype) void {
    commands.setResource(Mouse, .{});
    commands.setResource(Keyboard, .{});
}

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = updateFrameCounts, .stage = .last }, // Increment after systems check
        .{ .system = resetPerFrameState, .stage = .last },
    },
    .event_handlers = &.{handleEvent},
};

// Tests
test "Mouse.isPressed returns true only on first frame" {
    var mouse = Mouse{};

    // Simulate button press
    mouse.left_button = true;
    mouse.held_frame_map.set(.LEFT, 1);

    try std.testing.expect(mouse.isPressed(.LEFT));

    // After incrementing frame count
    mouse.held_frame_map.set(.LEFT, 2);
    try std.testing.expect(!mouse.isPressed(.LEFT));
}

test "Mouse.isReleased detects button release" {
    var mouse = Mouse{};

    // Button was held for 1 frame
    mouse.left_button = false; // Released now
    mouse.held_frame_map.set(.LEFT, 1);

    try std.testing.expect(mouse.isReleased(.LEFT));

    // After frame count reset
    mouse.held_frame_map.set(.LEFT, 0);
    try std.testing.expect(!mouse.isReleased(.LEFT));
}

test "Mouse.isReleased detects release after multi-frame hold" {
    var mouse = Mouse{};

    // Simulate button held for 10 frames
    mouse.left_button = false; // Released now
    mouse.held_frame_map.set(.LEFT, 10);

    // Should detect release even when held_frame_map > 1
    try std.testing.expect(mouse.isReleased(.LEFT));

    // After cleanup resets frame count
    mouse.held_frame_map.set(.LEFT, 0);
    try std.testing.expect(!mouse.isReleased(.LEFT));
}

test "Mouse.isHeld returns true while button is down" {
    var mouse = Mouse{};

    mouse.left_button = false;
    try std.testing.expect(!mouse.isHeld(.LEFT));

    mouse.left_button = true;
    try std.testing.expect(mouse.isHeld(.LEFT));
}

test "Mouse.heldFrames tracks button hold duration" {
    var mouse = Mouse{};

    try std.testing.expectEqual(@as(u32, 0), mouse.heldFrames(.LEFT));

    mouse.held_frame_map.set(.LEFT, 1);
    try std.testing.expectEqual(@as(u32, 1), mouse.heldFrames(.LEFT));

    mouse.held_frame_map.set(.LEFT, 10);
    try std.testing.expectEqual(@as(u32, 10), mouse.heldFrames(.LEFT));
}

test "Mouse button tracking works for all buttons" {
    var mouse = Mouse{};

    // Test left button
    mouse.left_button = true;
    mouse.held_frame_map.set(.LEFT, 1);
    try std.testing.expect(mouse.isPressed(.LEFT));
    try std.testing.expect(mouse.isHeld(.LEFT));

    // Test right button
    mouse.right_button = true;
    mouse.held_frame_map.set(.RIGHT, 1);
    try std.testing.expect(mouse.isPressed(.RIGHT));
    try std.testing.expect(mouse.isHeld(.RIGHT));

    // Test middle button
    mouse.middle_button = true;
    mouse.held_frame_map.set(.MIDDLE, 1);
    try std.testing.expect(mouse.isPressed(.MIDDLE));
    try std.testing.expect(mouse.isHeld(.MIDDLE));
}

test "Keyboard frame counts persist while held" {
    var keyboard = Keyboard{};

    const w_index: usize = @intCast(@intFromEnum(sokol.app.Keycode.W));
    keyboard.keys.set(w_index);
    keyboard.held_frame_map.set(.W, 1);

    keyboard.incrementHeldKeyFrames();
    keyboard.cleanupReleasedKeys();
    try std.testing.expectEqual(@as(u32, 2), keyboard.held_frame_map.get(.W));

    keyboard.incrementHeldKeyFrames();
    keyboard.cleanupReleasedKeys();
    try std.testing.expectEqual(@as(u32, 3), keyboard.held_frame_map.get(.W));

    keyboard.keys.unset(w_index);
    keyboard.cleanupReleasedKeys();
    try std.testing.expectEqual(@as(u32, 0), keyboard.held_frame_map.get(.W));
}

test "Keyboard.isReleased detects release after multi-frame hold" {
    var keyboard = Keyboard{};

    // Simulate key held for 15 frames
    keyboard.held_frame_map.set(.W, 15);
    // Key is now released (not in bitset)

    // Should detect release even when held_frame_map > 1
    try std.testing.expect(keyboard.isReleased(.W));

    // After cleanup resets frame count
    keyboard.held_frame_map.set(.W, 0);
    try std.testing.expect(!keyboard.isReleased(.W));
}
