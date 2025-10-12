const application_module = @import("core/application.zig");
pub const run = application_module.run;

const system_module = @import("core/system.zig");
pub const Stage = system_module.Stage;
pub const SystemRegistry = system_module.SystemRegistry;

pub const GraphicsPlugin = @import("plugins/graphics/root.zig");

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
