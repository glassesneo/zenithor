const std = @import("std");
const sparze = @import("sparze");
const sokol = @import("sokol");

const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;

/// Mouse input resource containing mouse position, deltas, scroll, and button states
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

    pub const serialized = false;
};

/// Keyboard input resource containing key states and modifiers
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

        // Released means: was in map (was held), but not in bitset anymore
        const was_held = self.held_frame_map.get(key) == 1;
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

    pub const serialized = false;
};

pub const Components = .{};
pub const Resources = .{
    Mouse,
    Keyboard,
};

pub const Events = .{};

fn handleEvent(event: sokol.app.Event, world: anytype) !void {
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
                .LEFT => mouse.left_button = true,
                .RIGHT => mouse.right_button = true,
                .MIDDLE => mouse.middle_button = true,
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
            keyboard.keys.set(@intCast(key_code));
            // Set to 1 on first press (updateFrameCounts will increment)
            keyboard.held_frame_map.set(event.key_code, 1);
            keyboard.modifiers = event.modifiers;
        },
        .KEY_UP => {
            const key_code: i32 = @intFromEnum(event.key_code);
            if (key_code >= 0 and key_code < 512) {
                keyboard.keys.unset(@intCast(key_code));
                _ = keyboard.held_frame_map.set(event.key_code, 0);
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

fn resetPerFrameState(mouse: sparze.Resource(Mouse), keyboard: sparze.Resource(Keyboard)) !void {
    // Reset per-frame deltas and buffers
    mouse.value.dx = 0.0;
    mouse.value.dy = 0.0;
    mouse.value.scroll_x = 0.0;
    mouse.value.scroll_y = 0.0;
    keyboard.value.char_count = 0;
}

fn updateFrameCounts(keyboard: sparze.Resource(Keyboard)) !void {
    // Increment frame count for all held keys
    var iter = keyboard.value.keys.iterator(.{});
    while (iter.next()) |index| {
        const key: sokol.app.Keycode = @enumFromInt(index);
        keyboard.value.held_frame_map.getPtr(key).* += 1;
    }
}

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Initialize resources with default values
    try world.setResource(Mouse, .{});

    try world.setResource(Keyboard, .{});

    // Register event handler for direct Sokol input (with World access)
    registry.registerEventHandler(handleEvent);

    // Register systems at frame end
    registry.registerSystem(updateFrameCounts, .last); // Increment after systems check
    registry.registerSystem(resetPerFrameState, .last);
}

