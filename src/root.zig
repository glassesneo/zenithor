const sparze = @import("sparze");
pub const World = sparze.World;

const application_module = @import("core/application.zig");
pub const init = application_module.Application.init;
pub const deinit = application_module.Application.deinit;
pub const registerPlugin = application_module.Application.registerPlugin;
pub const run = application_module.Application.run;

pub const GraphicsPlugin = @import("plugins/graphics/root.zig");

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
