const sparze = @import("sparze");
const sokol = @import("sokol");

const system_module = @import("system.zig");
const SystemRegistry = system_module.SystemRegistry;

pub const Transform = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn format(self: Transform, writer: anytype) !void {
        try writer.print("Transform(x: {d:.2}, y: {d:.2}, z: {d:.2})", .{ self.x, self.y, self.z });
    }
};

pub const Components = .{Transform};

pub fn build(registry: SystemRegistry) !void {
    _ = registry;
}

const std = @import("std");
