const zenithor = @import("zenithor");
const GamePlugin = @import("game_example");

// IMPORTANT: We only specify GamePlugin here!
// The dependency system automatically includes:
// - TimePlugin (required by GamePlugin)
// - InputPlugin (required by GamePlugin)
// - GraphicsPlugin (required by GamePlugin)
//
// This demonstrates auto-include functionality.

pub fn main() void {
    zenithor.run(.{GamePlugin});
}
