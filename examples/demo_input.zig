const std = @import("std");
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;
const ImGuiPlugin = @import("imgui_plugin");
const InputPlugin = @import("input_plugin");
const sokol = @import("sokol");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, Game }, .{});
}

fn setupPassAction(options: zenithor.ResourceMut(GraphicsPlugin.RenderingOptions)) void {
    options.value.pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.15, .b = 0.2, .a = 1.0 };
}

fn displayInputState(
    mouse: zenithor.Resource(InputPlugin.Mouse),
    keyboard: zenithor.Resource(InputPlugin.Keyboard),
) void {
    const pos = ImGuiPlugin.ImVec2{ .x = 10, .y = 10 };
    ImGuiPlugin.setNextWindowPos(pos, .Once);

    const size = ImGuiPlugin.ImVec2{ .x = 500, .y = 700 };
    ImGuiPlugin.setNextWindowSize(size, .Once);

    var window_open = true;
    if (ImGuiPlugin.begin("Input Demo", &window_open, .None)) {
        // === MOUSE SECTION ===
        ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.2, .y = 1.0, .z = 0.5, .w = 1.0 }, "MOUSE INPUT");
        ImGuiPlugin.separator();
        ImGuiPlugin.spacing();

        // Position
        ImGuiPlugin.textFmt("Position: ({any}, {any})", .{ mouse.value.x, mouse.value.y });

        // Delta (movement since last frame)
        ImGuiPlugin.textFmt("Delta: ({d:.1}, {d:.1})", .{ mouse.value.dx, mouse.value.dy });
        if (mouse.value.dx != 0 or mouse.value.dy != 0) {
            ImGuiPlugin.sameLine();
            ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.8, .y = 0.8, .z = 0.2, .w = 1.0 }, "MOVING");
        }

        // Buttons
        ImGuiPlugin.text("Buttons:");
        ImGuiPlugin.indent();
        if (mouse.value.left_button) {
            ImGuiPlugin.text("Left:   PRESSED");
        } else {
            ImGuiPlugin.text("Left:   released");
        }
        if (mouse.value.right_button) {
            ImGuiPlugin.text("Right:  PRESSED");
        } else {
            ImGuiPlugin.text("Right:  released");
        }
        if (mouse.value.middle_button) {
            ImGuiPlugin.text("Middle: PRESSED");
        } else {
            ImGuiPlugin.text("Middle: released");
        }
        ImGuiPlugin.unindent();

        // Scroll
        ImGuiPlugin.textFmt("Scroll Y: {d:.1}", .{mouse.value.scroll_y});

        ImGuiPlugin.spacing();
        ImGuiPlugin.separator();
        ImGuiPlugin.spacing();

        // === KEYBOARD SECTION ===
        ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 1.0, .y = 0.5, .z = 0.2, .w = 1.0 }, "KEYBOARD INPUT");
        ImGuiPlugin.separator();
        ImGuiPlugin.spacing();

        // Special keys
        ImGuiPlugin.text("Special Keys:");
        ImGuiPlugin.indent();
        if (keyboard.value.modifiers & 0x1 != 0) {
            ImGuiPlugin.text("Shift:  DOWN");
        } else {
            ImGuiPlugin.text("Shift:  up");
        }
        if (keyboard.value.modifiers & 0x2 != 0) {
            ImGuiPlugin.text("Ctrl:   DOWN");
        } else {
            ImGuiPlugin.text("Ctrl:   up");
        }
        if (keyboard.value.modifiers & 0x4 != 0) {
            ImGuiPlugin.text("Alt:    DOWN");
        } else {
            ImGuiPlugin.text("Alt:    up");
        }
        if (keyboard.value.modifiers & 0x8 != 0) {
            ImGuiPlugin.text("Super:  DOWN");
        } else {
            ImGuiPlugin.text("Super:  up");
        }
        ImGuiPlugin.unindent();

        ImGuiPlugin.spacing();

        // Letter keys (A-Z)
        ImGuiPlugin.text("Letter Keys:");
        ImGuiPlugin.indent();
        var letter_count: usize = 0;
        inline for ('A'..'Z') |key| {
            const key_code: usize = @intCast(key);
            if (keyboard.value.keys.isSet(key_code)) {
                const key_str = switch (key) {
                    'A' => "A: DOWN",
                    'B' => "B: DOWN",
                    'C' => "C: DOWN",
                    'D' => "D: DOWN",
                    'E' => "E: DOWN",
                    'F' => "F: DOWN",
                    'G' => "G: DOWN",
                    'H' => "H: DOWN",
                    'I' => "I: DOWN",
                    'J' => "J: DOWN",
                    'K' => "K: DOWN",
                    'L' => "L: DOWN",
                    'M' => "M: DOWN",
                    'N' => "N: DOWN",
                    'O' => "O: DOWN",
                    'P' => "P: DOWN",
                    'Q' => "Q: DOWN",
                    'R' => "R: DOWN",
                    'S' => "S: DOWN",
                    'T' => "T: DOWN",
                    'U' => "U: DOWN",
                    'V' => "V: DOWN",
                    'W' => "W: DOWN",
                    'X' => "X: DOWN",
                    'Y' => "Y: DOWN",
                    'Z' => "Z: DOWN",
                    else => "",
                };
                if (key_str.len > 0) {
                    ImGuiPlugin.text(key_str);
                }
                letter_count += 1;
            }
        }
        if (letter_count == 0) {
            ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "(none)");
        }
        ImGuiPlugin.unindent();

        ImGuiPlugin.spacing();

        // Number keys (0-9)
        ImGuiPlugin.text("Number Keys:");
        ImGuiPlugin.indent();
        var number_count: usize = 0;
        inline for ('0'..'9') |key| {
            const key_code: usize = @intCast(key);
            if (keyboard.value.keys.isSet(key_code)) {
                const key_str = switch (key) {
                    '0' => "0: DOWN",
                    '1' => "1: DOWN",
                    '2' => "2: DOWN",
                    '3' => "3: DOWN",
                    '4' => "4: DOWN",
                    '5' => "5: DOWN",
                    '6' => "6: DOWN",
                    '7' => "7: DOWN",
                    '8' => "8: DOWN",
                    '9' => "9: DOWN",
                    else => "",
                };
                if (key_str.len > 0) {
                    ImGuiPlugin.text(key_str);
                }
                number_count += 1;
            }
        }
        if (number_count == 0) {
            ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "(none)");
        }
        ImGuiPlugin.unindent();

        ImGuiPlugin.spacing();

        // Function keys (F1-F12)
        ImGuiPlugin.text("Function Keys:");
        ImGuiPlugin.indent();
        var function_count: usize = 0;
        inline for (1..13) |key_num| {
            const key_code = @intFromEnum(sokol.app.Keycode.F1) + (key_num - 1);
            if (key_code < 512 and keyboard.value.keys.isSet(key_code)) {
                ImGuiPlugin.textFmt("F{d}: DOWN", .{key_num});
                function_count += 1;
            }
        }
        if (function_count == 0) {
            ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "(none)");
        }
        ImGuiPlugin.unindent();

        ImGuiPlugin.spacing();

        // Arrow keys
        ImGuiPlugin.text("Arrow Keys:");
        ImGuiPlugin.indent();
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.UP))) {
            ImGuiPlugin.text("Up:    DOWN");
        } else {
            ImGuiPlugin.text("Up:    up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.DOWN))) {
            ImGuiPlugin.text("Down:  DOWN");
        } else {
            ImGuiPlugin.text("Down:  up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.LEFT))) {
            ImGuiPlugin.text("Left:  DOWN");
        } else {
            ImGuiPlugin.text("Left:  up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.RIGHT))) {
            ImGuiPlugin.text("Right: DOWN");
        } else {
            ImGuiPlugin.text("Right: up");
        }
        ImGuiPlugin.unindent();

        ImGuiPlugin.spacing();

        // Other keys
        ImGuiPlugin.text("Other Keys:");
        ImGuiPlugin.indent();
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.SPACE))) {
            ImGuiPlugin.text("Space:     DOWN");
        } else {
            ImGuiPlugin.text("Space:     up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.ENTER))) {
            ImGuiPlugin.text("Enter:     DOWN");
        } else {
            ImGuiPlugin.text("Enter:     up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.BACKSPACE))) {
            ImGuiPlugin.text("Backspace: DOWN");
        } else {
            ImGuiPlugin.text("Backspace: up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.TAB))) {
            ImGuiPlugin.text("Tab:       DOWN");
        } else {
            ImGuiPlugin.text("Tab:       up");
        }
        if (keyboard.value.keys.isSet(@intFromEnum(sokol.app.Keycode.ESCAPE))) {
            ImGuiPlugin.text("Escape:    DOWN");
        } else {
            ImGuiPlugin.text("Escape:    up");
        }
        ImGuiPlugin.unindent();
    }
    ImGuiPlugin.end();
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setupPassAction, .stage = .first },
        },
        .main = &.{
            .{ .system = displayInputState, .stage = .render },
        },
    };
};
