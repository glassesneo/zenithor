pub const PluginInfo = struct {
    name: []const u8,
    path: []const u8,
    module: *std.Build.Module,
};

const std = @import("std");
