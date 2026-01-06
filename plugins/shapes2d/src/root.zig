const sparze = @import("sparze");
const Query = sparze.Query;
const sokol = @import("sokol");

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Stage = zenithor.Stage;
const std = @import("std");
const builtin = @import("builtin");
const RendererPlugin = @import("renderer_plugin");

const is_debug = builtin.mode == .Debug;

// =============================================================================
// 2D Shape Components
// =============================================================================

pub const Point = struct {};

pub const Line = struct {
    x: f32,
    y: f32,

    pub fn format(self: Line, writer: anytype) !void {
        try writer.print("Line(end: x: {d:.2}, y: {d:.2})", .{ self.x, self.y });
    }
};

pub const Triangle = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,

    pub fn format(self: Triangle, writer: anytype) !void {
        try writer.print("Triangle(v1: ({d:.2}, {d:.2}), v2: ({d:.2}, {d:.2}), v3: ({d:.2}, {d:.2}))", .{
            self.x1, self.y1,
            self.x2, self.y2,
            self.x3, self.y3,
        });
    }
};

pub const Rectangle = struct {
    x: f32,
    y: f32,

    pub fn format(self: Rectangle, writer: anytype) !void {
        try writer.print("Rectangle(width: {d:.2}, height: {d:.2})", .{ self.x, self.y });
    }
};

pub const Circle = struct {
    radius: f32,
    segments: u32 = 32, // Number of segments to approximate the circle

    pub fn format(self: Circle, writer: anytype) !void {
        try writer.print("Circle(radius: {d:.2}, segments: {})", .{ self.radius, self.segments });
    }
};

// =============================================================================
// 2D Drawing Systems
// =============================================================================

fn drawPoint(points: Query(struct { Point, Transform, ?Color })) void {
    sokol.gl.beginPoints();
    for (points.entities) |entity| {
        if (!points.filter(entity)) continue;
        if (points.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = points.getComponentMut(entity, Transform);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
    }
    sokol.gl.end();
}

fn drawLine(lines: Query(struct { Line, Transform, ?Color })) void {
    sokol.gl.beginLines();
    for (lines.entities) |entity| {
        if (!lines.filter(entity)) continue;
        if (lines.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = lines.getComponentMut(entity, Transform);
        const line = lines.getComponentMut(entity, Line);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + line.x, transform.y + line.y, transform.z);
    }
    sokol.gl.end();
}

fn drawTriangle(triangles: Query(struct { Triangle, Transform, ?Color })) void {
    sokol.gl.beginTriangles();
    for (triangles.entities) |entity| {
        if (!triangles.filter(entity)) continue;
        if (triangles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = triangles.getComponentMut(entity, Transform);
        const triangle = triangles.getComponentMut(entity, Triangle);
        sokol.gl.v3f(transform.x + triangle.x1, transform.y + triangle.y1, transform.z);
        sokol.gl.v3f(transform.x + triangle.x2, transform.y + triangle.y2, transform.z);
        sokol.gl.v3f(transform.x + triangle.x3, transform.y + triangle.y3, transform.z);
    }
    sokol.gl.end();
}

fn drawRectangle(rectangles: Query(struct { Rectangle, Transform, ?Color })) void {
    sokol.gl.beginQuads();
    for (rectangles.entities) |entity| {
        if (!rectangles.filter(entity)) continue;
        if (rectangles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = rectangles.getComponentMut(entity, Transform);
        const rectangle = rectangles.getComponentMut(entity, Rectangle);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y + rectangle.y, transform.z);
        sokol.gl.v3f(transform.x, transform.y + rectangle.y, transform.z);
    }
    sokol.gl.end();
}

fn drawCircle(circles: Query(struct { Circle, Transform, ?Color })) void {
    sokol.gl.beginTriangles();
    for (circles.entities) |entity| {
        if (!circles.filter(entity)) continue;
        const transform = circles.getComponentMut(entity, Transform);
        const circle = circles.getComponentMut(entity, Circle);

        if (circles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }

        // Draw circle as triangle fan
        if (circle.segments == 0) {
            if (is_debug) {
                @panic("Circle.segments must be at least 1 to avoid division by zero");
            }
            continue;
        }
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(circle.segments));

        for (0..circle.segments) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
            const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step;

            const x1 = transform.x + circle.radius * @cos(angle1);
            const y1 = transform.y + circle.radius * @sin(angle1);
            const x2 = transform.x + circle.radius * @cos(angle2);
            const y2 = transform.y + circle.radius * @sin(angle2);

            // Triangle from center to two consecutive points on circumference
            sokol.gl.v3f(transform.x, transform.y, transform.z); // Center
            sokol.gl.v3f(x1, y1, transform.z); // Point 1 on circumference
            sokol.gl.v3f(x2, y2, transform.z); // Point 2 on circumference
        }
    }
    sokol.gl.end();
}

// =============================================================================
// Plugin Declarations
// =============================================================================

pub const Components = .{
    Point,
    Line,
    Triangle,
    Rectangle,
    Circle,
};

pub const Resources = .{};

pub const Events = .{};

pub const Requires = .{RendererPlugin};

pub const systems = .{
    .main = &.{
        .{ .system = drawPoint, .stage = .render },
        .{ .system = drawLine, .stage = .render },
        .{ .system = drawTriangle, .stage = .render },
        .{ .system = drawRectangle, .stage = .render },
        .{ .system = drawCircle, .stage = .render },
    },
};
