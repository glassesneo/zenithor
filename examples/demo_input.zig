const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const InputPlugin = zenithor.InputPlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, Game });
}

fn setup(commands: anytype) !void {
    // Create ImGui windows to display input state
    _ = try commands.createEntityWith(.{
        BuiltinPlugin.Transform{ .x = 10, .y = 10, .z = 0 },
        ImGuiPlugin.Window{ .title = "Input Demo", .open = true },
    });
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
            ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[MOVING]");
        }

        ig.igSpacing();

        // Buttons
        const left_color = if (mouse.value.left_button)
            ig.ImVec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }
        else
            ig.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 };
        const right_color = if (mouse.value.right_button)
            ig.ImVec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }
        else
            ig.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 };
        const middle_color = if (mouse.value.middle_button)
            ig.ImVec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }
        else
            ig.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 };

        const left_text: [*:0]const u8 = if (mouse.value.left_button) "[LEFT]" else "LEFT";
        const right_text: [*:0]const u8 = if (mouse.value.right_button) "[RIGHT]" else "RIGHT";
        const middle_text: [*:0]const u8 = if (mouse.value.middle_button) "[MIDDLE]" else "MIDDLE";

        ig.igTextColored(left_color, "%s", left_text);
        ig.igSameLine();
        ig.igTextColored(right_color, "%s", right_text);
        ig.igSameLine();
        ig.igTextColored(middle_color, "%s", middle_text);

        ig.igSpacing();

        // Scroll
        ig.igText("Scroll: (%.1f, %.1f)", mouse.value.scroll_x, mouse.value.scroll_y);
        if (mouse.value.scroll_y > 0) {
            ig.igSameLine();
            ig.igTextColored(.{ .x = 0.0, .y = 1.0, .z = 1.0, .w = 1.0 }, "%s", "[SCROLL UP]");
        } else if (mouse.value.scroll_y < 0) {
            ig.igSameLine();
            ig.igTextColored(.{ .x = 0.0, .y = 1.0, .z = 1.0, .w = 1.0 }, "%s", "[SCROLL DOWN]");
        }

        ig.igSpacing();
        ig.igSpacing();

        // === KEYBOARD SECTION ===
        ig.igTextColored(.{ .x = 1.0, .y = 0.5, .z = 0.2, .w = 1.0 }, "%s", "KEYBOARD INPUT");
        ig.igSeparator();
        ig.igSpacing();

        // Count pressed keys
        const pressed_count = keyboard.value.keys.count();
        ig.igText("Keys Pressed: %d", pressed_count);

        ig.igSpacing();

        // Modifiers
        const has_shift = (keyboard.value.modifiers & 0x1) != 0;
        const has_ctrl = (keyboard.value.modifiers & 0x2) != 0;
        const has_alt = (keyboard.value.modifiers & 0x4) != 0;
        const has_super = (keyboard.value.modifiers & 0x8) != 0;

        ig.igText("Modifiers:");
        ig.igSameLine();
        if (has_shift) ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[SHIFT]");
        if (has_shift) ig.igSameLine();
        if (has_ctrl) ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[CTRL]");
        if (has_ctrl) ig.igSameLine();
        if (has_alt) ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[ALT]");
        if (has_alt) ig.igSameLine();
        if (has_super) ig.igTextColored(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[SUPER]");
        if (!has_shift and !has_ctrl and !has_alt and !has_super) {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "%s", "None");
        }

        ig.igSpacing();

        // Character input
        ig.igText("Character Input:");
        if (keyboard.value.char_count > 0) {
            ig.igSameLine();
            ig.igTextColored(.{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }, "%s", "[TYPING]");
            for (0..keyboard.value.char_count) |i| {
                const char_code = keyboard.value.char_buffer[i];
                if (char_code < 128) {
                    ig.igText("  '%c' (U+%04X)", @as(u8, @intCast(char_code)), char_code);
                } else {
                    ig.igText("  U+%04X", char_code);
                }
            }
        } else {
            ig.igSameLine();
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "%s", "None this frame");
        }

        ig.igSpacing();
        ig.igSpacing();

        // === INSTRUCTIONS ===
        ig.igTextColored(.{ .x = 0.7, .y = 0.7, .z = 1.0, .w = 1.0 }, "%s", "INSTRUCTIONS");
        ig.igSeparator();
        ig.igSpacing();
        ig.igTextWrapped("%s", "Move your mouse, click buttons, scroll, and press keys to see live input updates!");
        ig.igSpacing();
        ig.igBulletText("%s", "Mouse movement shows position and delta");
        ig.igBulletText("%s", "Click left/right/middle mouse buttons");
        ig.igBulletText("%s", "Scroll with mouse wheel");
        ig.igBulletText("%s", "Press any keys (shows count)");
        ig.igBulletText("%s", "Hold Shift/Ctrl/Alt/Super modifiers");
        ig.igBulletText("%s", "Type characters to see input buffer");
    }
    ig.igEnd();
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(displayInputState, .render);
    }
};
