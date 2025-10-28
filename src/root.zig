const application_module = @import("core/application.zig");
pub const run = application_module.run;

const system_module = @import("core/system.zig");
pub const Stage = system_module.Stage;
pub const SystemRegistry = system_module.SystemRegistry;

pub const BuiltinPlugin = @import("core/builtin.zig");
pub const GraphicsPlugin = @import("plugins/graphics/root.zig");
pub const TimePlugin = @import("plugins/time/root.zig");
pub const ImGuiPlugin = @import("plugins/imgui/root.zig");
pub const InputPlugin = @import("plugins/input/root.zig");
pub const DebugPlugin = @import("plugins/debug/root.zig");

const sparze = @import("sparze");
pub const SingleQuery = sparze.SingleQuery;
pub const Query = sparze.Query;
pub const SingleTag = sparze.SingleTag;
pub const TagQuery = sparze.TagQuery;
pub const Group = sparze.Group;
pub const Resource = sparze.Resource;

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
