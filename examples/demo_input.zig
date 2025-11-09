const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const InputPlugin = @import("input_plugin");
const sokol = @import("sokol");
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, Game });
}

fn setupPassAction(pass_action: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    var action = pass_action.value;
    action.colors[0].clear_value = .{ .r = 0.1, .g = 0.15, .b = 0.2, .a = 1.0 };
}

fn displayInputState(
    mouse: zenithor.Resource(InputPlugin.Mouse),
    keyboard: zenithor.Resource(InputPlugin.Keyboard),
) !void {
    const pos = ig.ImVec2{ .x = 10, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 500, .y = 700 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Input Demo", &window_open, ig.ImGuiWindowFlags_None)) {
        // === MOUSE SECTION ===
        ig.igTextColored(.{ .x = 0.2, .y = 1.0, .z = 0.5, .w = 1.0 }, "%s", "MOUSE INPUT");
        ig.igSeparator();
        ig.igSpacing();

        // Position
        ig.igText("Position: (%.1f, %.1f)", mouse.value.x, mouse.value.y);

        // Delta (movement since last frame)
        ig.igText("Delta: (%.1f, %.1f)", mouse.value.dx, mouse.value.dy);
        if (mouse.value.dx != 0 or mouse.value.dy != 0) {
            ig.igSameLine();
            ig.igTextColored(.{ .x = 0.8, .y = 0.8, .z = 0.2, .w = 1.0 }, "%s", "MOVING");
        }

        // Buttons
        ig.igText("Buttons:");
        ig.igIndent();
        if (mouse.value.left_button) {
            ig.igText("Left:   PRESSED");
        } else {
            ig.igText("Left:   released");
        }
        if (mouse.value.right_button) {
            ig.igText("Right:  PRESSED");
        } else {
            ig.igText("Right:  released");
        }
        if (mouse.value.middle_button) {
            ig.igText("Middle: PRESSED");
        } else {
            ig.igText("Middle: released");
        }
        ig.igUnindent();

        // Scroll
        if (mouse.value.scroll_y != 0) {
            ig.igText("Scroll Y: %+.1f", mouse.value.scroll_y);
        } else {
            ig.igText("Scroll Y: 0");
        }

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // === KEYBOARD SECTION ===
        ig.igTextColored(.{ .x = 1.0, .y = 0.5, .z = 0.2, .w = 1.0 }, "%s", "KEYBOARD INPUT");
        ig.igSeparator();
        ig.igSpacing();

        // Special keys
        ig.igText("Special Keys:");
        ig.igIndent();
        if (keyboard.value.modifiers & 0x1 != 0) {
            ig.igText("Shift:  DOWN");
        } else {
            ig.igText("Shift:  up");
        }
        if (keyboard.value.modifiers & 0x2 != 0) {
            ig.igText("Ctrl:   DOWN");
        } else {
            ig.igText("Ctrl:   up");
        }
        if (keyboard.value.modifiers & 0x4 != 0) {
            ig.igText("Alt:    DOWN");
        } else {
            ig.igText("Alt:    up");
        }
        if (keyboard.value.modifiers & 0x8 != 0) {
            ig.igText("Super:  DOWN");
        } else {
            ig.igText("Super:  up");
        }
        ig.igUnindent();

        ig.igSpacing();

        // Letter keys (A-Z)
        ig.igText("Letter Keys:");
        ig.igIndent();
        var letter_count: usize = 0;
        inline for ('A'..'Z') |key| {
            const key_code: usize = @intCast(key);
            if (keyboard.value.keys.isSet(key_code)) {
                ig.igText("%c: DOWN", key);
                letter_count += 1;
            }
        }
        if (letter_count == 0) {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "%s", "(none)");
        }
        ig.igUnindent();

        ig.igSpacing();

        // Number keys (0-9)
        ig.igText("Number Keys:");
        ig.igIndent();
        var number_count: usize = 0;
        inline for ('0'..'9') |key| {
            const key_code: usize = @intCast(key);
            if (keyboard.value.keys.isSet(key_code)) {
                ig.igText("%c: DOWN", key);
                number_count += 1;
            }
        }
        if (number_count == 0) {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "%s", "(none)");
        }
        ig.igUnindent();

        ig.igSpacing();

        // Function keys (F1-F12)
        ig.igText("Function Keys:");
        ig.igIndent();
        var function_count: usize = 0;
        inline for (1..13) |key_num| {
            const key_code = @intFromEnum(sokol.app.Keycode.F1) + (key_num - 1);
            if (key_code < 512 and keyboard.value.keys.isSet(key_code)) {
                ig.igText("F%d: DOWN", key_num);
                function_count += 1;
            }
        }
        if (function_count == 0) {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "%s", "(none)");
        }
        ig.igUnindent();

        ig.igSpacing();

        // Arrow keys
        ig.igText("Arrow Keys:");
        ig.igIndent();
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.UP))) {
            ig.igText("Up:    DOWN");
        } else {
            ig.igText("Up:    up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.DOWN))) {
            ig.igText("Down:  DOWN");
        } else {
            ig.igText("Down:  up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.LEFT))) {
            ig.igText("Left:  DOWN");
        } else {
            ig.igText("Left:  up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.RIGHT))) {
            ig.igText("Right: DOWN");
        } else {
            ig.igText("Right: up");
        }
        ig.igUnindent();

        ig.igSpacing();

        // Other keys
        ig.igText("Other Keys:");
        ig.igIndent();
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.SPACE))) {
            ig.igText("Space:     DOWN");
        } else {
            ig.igText("Space:     up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.ENTER))) {
            ig.igText("Enter:     DOWN");
        } else {
            ig.igText("Enter:     up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.BACKSPACE))) {
            ig.igText("Backspace: DOWN");
        } else {
            ig.igText("Backspace: up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.TAB))) {
            ig.igText("Tab:       DOWN");
        } else {
            ig.igText("Tab:       up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.ESCAPE))) {
            ig.igText("Escape:    DOWN");
        } else {
            ig.igText("Escape:    up");
        }
        ig.igUnindent();
    }
    ig.igEnd();
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setupPassAction, .first);
        registry.registerSystem(displayInputState, .render);
    }
};