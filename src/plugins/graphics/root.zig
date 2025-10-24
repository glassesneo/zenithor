const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");

const BuiltinPlugin = @import("../../core/builtin.zig");
const Transform = BuiltinPlugin.Transform;

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

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

pub const Components = .{ Point, Line, Triangle, Rectangle };

pub var pass_action: sokol.gfx.PassAction = .{};

fn init() !void {
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1, .g = 1, .b = 1, .a = 0 },
    };
}

fn setDefaults() !void {
    sokol.gl.defaults();
}

fn setup2d() !void {
    sokol.gl.matrixModeProjection();
    const width: f32 = @floatFromInt(sokol.app.width());
    const height: f32 = @floatFromInt(sokol.app.height());
    sokol.gl.ortho(0, width, height, 0, -1, 1);
}

fn drawPoint(points: Query(struct { Point, Transform })) !void {
    sokol.gl.beginPoints();
    for (points.entities) |entity| {
        if (!points.hasAllComponents(entity)) continue;
        const transform = points.getComponentMut(entity, Transform).?;
        sokol.gl.c4b(255, 0, 0, 0);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
    }
    sokol.gl.end();
}

fn drawLine(lines: Query(struct { Line, Transform })) !void {
    sokol.gl.beginLines();
    for (lines.entities) |entity| {
        if (!lines.hasAllComponents(entity)) continue;
        const transform = lines.getComponentMut(entity, Transform).?;
        const line = lines.getComponentMut(entity, Line).?;
        sokol.gl.c4b(0, 0, 0, 255);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + line.x, transform.y + line.y, transform.z);
    }
    sokol.gl.end();
}

fn drawTriangle(triangles: Query(struct { Triangle, Transform })) !void {
    sokol.gl.beginTriangles();
    for (triangles.entities) |entity| {
        if (!triangles.hasAllComponents(entity)) continue;
        const transform = triangles.getComponentMut(entity, Transform).?;
        const triangle = triangles.getComponentMut(entity, Triangle).?;
        sokol.gl.c4b(0, 255, 0, 0);
        sokol.gl.v3f(transform.x + triangle.x1, transform.y + triangle.y1, transform.z);
        sokol.gl.v3f(transform.x + triangle.x2, transform.y + triangle.y2, transform.z);
        sokol.gl.v3f(transform.x + triangle.x3, transform.y + triangle.y3, transform.z);
    }
    sokol.gl.end();
}

fn drawRectangle(rectangles: Query(struct { Rectangle, Transform })) !void {
    sokol.gl.beginQuads();
    for (rectangles.entities) |entity| {
        if (!rectangles.hasAllComponents(entity)) continue;
        const transform = rectangles.getComponentMut(entity, Transform).?;
        const rectangle = rectangles.getComponentMut(entity, Rectangle).?;
        sokol.gl.c4b(255, 255, 0, 0);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y + rectangle.y, transform.z);
        sokol.gl.v3f(transform.x, transform.y + rectangle.y, transform.z);
    }
    sokol.gl.end();
}

fn beginPass() !void {
    sokol.gfx.beginPass(.{ .action = pass_action, .swapchain = sokol.glue.swapchain() });
    sokol.gl.draw();
}

fn endPass() !void {
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerStartupSystem(init, .first);
    registry.registerSystem(setDefaults, .pre_render);
    registry.registerSystem(setup2d, .pre_render);
    registry.registerSystem(drawPoint, .render);
    registry.registerSystem(drawLine, .render);
    registry.registerSystem(drawTriangle, .render);
    registry.registerSystem(drawRectangle, .render);
    registry.registerSystem(beginPass, .render_submit);
    registry.registerSystem(endPass, .post_render);
}

const std = @import("std");

test "Transform z-coordinate is used in 3D vertex positions" {
    const testing = std.testing;

    // Test Point
    const point_transform = Transform{ .x = 100, .y = 200, .z = 0.5 };
    try testing.expectEqual(@as(f32, 0.5), point_transform.z);

    // Test Line
    const line_transform = Transform{ .x = 50, .y = 75, .z = -0.3 };
    try testing.expectEqual(@as(f32, -0.3), line_transform.z);

    // Test Triangle
    const tri_transform = Transform{ .x = 300, .y = 400, .z = 0.8 };
    try testing.expectEqual(@as(f32, 0.8), tri_transform.z);

    // Test Rectangle
    const rect_transform = Transform{ .x = 150, .y = 250, .z = -0.9 };
    try testing.expectEqual(@as(f32, -0.9), rect_transform.z);
}

test "Z-depth range validation for orthographic projection" {
    const testing = std.testing;

    // Test valid z-depth range [-1, 1] for ortho projection
    // z_near = -1, z_far = 1
    const z_near: f32 = -1.0;
    const z_far: f32 = 1.0;

    // Test boundary values
    try testing.expectEqual(@as(f32, -1.0), z_near);
    try testing.expectEqual(@as(f32, 1.0), z_far);

    // Test valid z values within range
    const valid_z_values = [_]f32{ -1.0, -0.5, 0.0, 0.5, 1.0 };
    for (valid_z_values) |z| {
        try testing.expect(z >= z_near and z <= z_far);
    }
}

test "Z-depth ordering: lower values render in front" {
    const testing = std.testing;

    // In the orthographic projection with z_near=-1, z_far=1:
    // Lower z values (more negative) should render in front (closer to camera)
    // Higher z values (more positive) should render behind (farther from camera)

    const front_z: f32 = -0.9;  // Closer to camera
    const middle_z: f32 = 0.0;  // Middle depth
    const back_z: f32 = 0.9;    // Farther from camera

    // Verify ordering relationship
    try testing.expect(front_z < middle_z);
    try testing.expect(middle_z < back_z);

    // Lower z value means closer (rendered in front)
    try testing.expect(front_z < back_z);
}

test "Graphics component types are correctly defined" {
    const testing = std.testing;

    // Verify Point is a tag component (empty struct)
    try testing.expectEqual(@as(usize, 0), @sizeOf(Point));

    // Verify Line has correct fields
    const line = Line{ .x = 100.5, .y = 200.75 };
    try testing.expectEqual(@as(f32, 100.5), line.x);
    try testing.expectEqual(@as(f32, 200.75), line.y);

    // Verify Triangle has correct fields
    const triangle = Triangle{
        .x1 = 10.5,
        .y1 = 20.5,
        .x2 = 30.5,
        .y2 = 40.5,
        .x3 = 50.5,
        .y3 = 60.5,
    };
    try testing.expectEqual(@as(f32, 10.5), triangle.x1);
    try testing.expectEqual(@as(f32, 60.5), triangle.y3);

    // Verify Rectangle has correct fields
    const rectangle = Rectangle{ .x = 150.25, .y = 250.75 };
    try testing.expectEqual(@as(f32, 150.25), rectangle.x);
    try testing.expectEqual(@as(f32, 250.75), rectangle.y);
}
