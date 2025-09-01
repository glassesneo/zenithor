const application_module = @import("core/application.zig");
pub const Application = application_module.Application;

const plugin_module = @import("core/plugin.zig");
pub const Plugin = plugin_module.Plugin;

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
