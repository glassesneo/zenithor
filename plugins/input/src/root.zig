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
    modifiers: u32 = 0, // Modifier key bitmask (Shift, Ctrl, Alt, Super)
    char_buffer: [32]u32 = undefined, // UTF-32 character input buffer
    char_count: usize = 0, // Number of characters in buffer this frame

    pub const serialized = false;
};

pub const Components = .{};
pub const Resources = .{
    Mouse,
    Keyboard,
};

pub const Events = .{};

fn handleEvent(event: sokol.app.Event, world: anytype) !void {
    const mouse = world.getResourcePtrMut(Mouse);
    const keyboard = world.getResourcePtrMut(Keyboard);

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
            if (key_code >= 0 and key_code < 512) {
                keyboard.keys.set(@intCast(key_code));
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

fn resetPerFrameState(mouse: sparze.Resource(Mouse), keyboard: sparze.Resource(Keyboard)) !void {
    // Reset per-frame deltas and buffers
    mouse.value.dx = 0.0;
    mouse.value.dy = 0.0;
    mouse.value.scroll_x = 0.0;
    mouse.value.scroll_y = 0.0;
    keyboard.value.char_count = 0;
}

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Initialize resources with default values
    try world.setResource(Mouse, .{});
    try world.setResource(Keyboard, .{});

    // Register event handler for direct Sokol input (with World access)
    registry.registerEventHandler(handleEvent);

    // Register system to reset per-frame state at frame end
    registry.registerSystem(resetPerFrameState, .last);
}
