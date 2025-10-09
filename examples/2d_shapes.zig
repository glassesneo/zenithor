const zenithor = @import("zenithor");
const RegisterFunc = zenithor.RegisterFunc;

pub fn main() !void {
    zenithor.run(.{ zenithor.GraphicsPlugin, Game });
}

fn changeColor() !void {
    const g = zenithor.GraphicsPlugin.pass_action.colors[0].clear_value.g + 0.01;
    zenithor.GraphicsPlugin.pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
}

const Game = struct {
    pub const Components = .{};

    pub fn build(
        registerSystem: RegisterFunc,
        registerStartupSystem: RegisterFunc,
        registerTerminateSystem: RegisterFunc,
    ) !void {
        _ = registerStartupSystem;
        _ = registerTerminateSystem;
        registerSystem(changeColor, .render);
    }
};
