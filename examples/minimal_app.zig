/// Example: Minimal Application + Plugin Wiring
///
/// Demonstrates the basic structure of a Zenithor application:
/// - zenithor.run() with plugin tuple and options placeholder
/// - BuiltinPlugin (Transform, Color) is auto-included
/// - Custom game plugin with Components/Events/Resources/systems
/// - A single startup system creating an entity
///
/// See: src/core/CLAUDE.md
const zenithor = @import("zenithor");
const GraphicsPlugin = @import("graphics_plugin").Default;
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");

pub fn main() !void {
    // Entry point: pass plugin tuple and options placeholder
    // BuiltinPlugin is added automatically
    zenithor.run(.{ GraphicsPlugin, Game }, .{});
}

// Game plugin definition
const Game = struct {
    // Declare component, resource, and event types (can be empty)
    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    // Declarative system registration
    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
    };
};

// Single startup system: creates a centered white circle
fn setup(commands: anytype) !void {
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 50, .segments = 48 },
        zenithor.Transform{ .x = 640, .y = 400, .z = 0 },
        zenithor.Color.white,
    });
}
