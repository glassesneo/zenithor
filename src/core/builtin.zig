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

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn format(self: Color, writer: anytype) !void {
        try writer.print("Color(r: {}, g: {}, b: {}, a: {})", .{ self.r, self.g, self.b, self.a });
    }

    // Predefined colors for convenience
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
    pub const cyan = Color{ .r = 0, .g = 255, .b = 255, .a = 255 };
    pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };
    pub const purple = Color{ .r = 128, .g = 0, .b = 128, .a = 255 };
};

pub const Components = .{ Transform, Color };

pub fn build(registry: SystemRegistry) !void {
    _ = registry;
}

const std = @import("std");
