const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");

const BuiltinPlugin = @import("../../core/builtin.zig");

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

pub const MousePosition = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub var mouse_position: MousePosition = .{};

pub const Components = .{};

fn handleEvent(event: sokol.app.Event) !void {
    switch (event.type) {
        .MOUSE_MOVE => {
            mouse_position = .{ .x = event.mouse_x, .y = event.mouse_y };
        },
        else => {},
    }
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerEventHandler(handleEvent);
}

const std = @import("std");
