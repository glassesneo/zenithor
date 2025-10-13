const sparze = @import("sparze");
const sokol = @import("sokol");

const system_module = @import("system.zig");
const SystemRegistry = system_module.SystemRegistry;

pub const Transform = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Components = .{Transform};

pub fn build(registry: SystemRegistry) !void {
    _ = registry;
}

const std = @import("std");
