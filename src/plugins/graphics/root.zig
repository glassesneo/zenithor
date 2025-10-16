const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");

const BuiltinPlugin = @import("../../core/builtin.zig");
const Transform = BuiltinPlugin.Transform;

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

pub const Point = struct {
    tag: u8 = 0,
};

pub const Line = struct {
    x: f32,
    y: f32,
};

pub const Triangle = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
};

pub const Rectangle = struct {
    x: f32,
    y: f32,
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
        sokol.gl.v2f(transform.x, transform.y);
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
        sokol.gl.v2f(transform.x, transform.y);
        sokol.gl.v2f(transform.x + line.x, transform.y + line.y);
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
        sokol.gl.v2f(transform.x + triangle.x1, transform.y + triangle.y1);
        sokol.gl.v2f(transform.x + triangle.x2, transform.y + triangle.y2);
        sokol.gl.v2f(transform.x + triangle.x3, transform.y + triangle.y3);
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
        sokol.gl.v2f(transform.x, transform.y);
        sokol.gl.v2f(transform.x + rectangle.x, transform.y);
        sokol.gl.v2f(transform.x + rectangle.x, transform.y + rectangle.y);
        sokol.gl.v2f(transform.x, transform.y + rectangle.y);
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
