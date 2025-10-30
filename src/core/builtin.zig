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
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    pub fn format(self: Color, writer: anytype) !void {
        try writer.print("Color(r: {d:.2}, g: {d:.2}, b: {d:.2}, a: {d:.2})", .{ self.r, self.g, self.b, self.a });
    }

    // Predefined colors for convenience
    pub const red = Color{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const green = Color{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const blue = Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const yellow = Color{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const cyan = Color{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const magenta = Color{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const white = Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const black = Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const orange = Color{ .r = 1.0, .g = 0.647, .b = 0.0, .a = 1.0 };
    pub const purple = Color{ .r = 0.502, .g = 0.0, .b = 0.502, .a = 1.0 };
};

pub const Components = .{
    Transform,
    Color,
};

pub const Events = .{};

const std = @import("std");
