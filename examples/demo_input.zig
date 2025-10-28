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
    // Create an ImGui window to display mouse position
    _ = try commands.createEntityWith(.{
        BuiltinPlugin.Transform{ .x = 100, .y = 100, .z = 0 },
        ImGuiPlugin.Window{ .title = "Mouse Position", .open = true },
    });

    // Set a nice background color
    GraphicsPlugin.pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.15, .b = 0.2, .a = 1.0 };
}

fn displayMousePosition(mouse: zenithor.Resource(InputPlugin.Mouse)) !void {
    const pos = ig.ImVec2{ .x = 100, .y = 100 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 300, .y = 150 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Mouse Position", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 0.2, .y = 1.0, .z = 0.5, .w = 1.0 }, "%s", "Live Mouse Tracking");
        ig.igSeparator();
        ig.igSpacing();

        // Display current mouse position
        ig.igText("X: %.1f pixels", mouse.value.x);
        ig.igText("Y: %.1f pixels", mouse.value.y);

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // Display as formatted text
        ig.igTextColored(.{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 }, "%s", "Position:");
        ig.igSameLine();
        ig.igText("(%.1f, %.1f)", mouse.value.x, mouse.value.y);

        ig.igSpacing();

        // Display button states
        const left_state: [*:0]const u8 = if (mouse.value.left_button) "Pressed" else "Released";
        const right_state: [*:0]const u8 = if (mouse.value.right_button) "Pressed" else "Released";
        const middle_state: [*:0]const u8 = if (mouse.value.middle_button) "Pressed" else "Released";
        ig.igText("Left Button: %s", left_state);
        ig.igText("Right Button: %s", right_state);
        ig.igText("Middle Button: %s", middle_state);

        ig.igSpacing();

        // Show hint text
        ig.igTextWrapped("%s", "Move your mouse around the window to see the coordinates update in real-time!");
    }
    ig.igEnd();
}

const Game = struct {
    pub const Components = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(displayMousePosition, .render);
    }
};
