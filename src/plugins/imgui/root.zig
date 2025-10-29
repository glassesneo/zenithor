const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");
const imgui_docking = @import("build_options").docking;
pub const ig = if (imgui_docking) @import("cimgui_docking") else @import("cimgui");

const BuiltinPlugin = @import("../../core/builtin.zig");
const Transform = BuiltinPlugin.Transform;

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

pub const Window = struct {
    title: [:0]const u8,
    open: bool = true,

    pub fn format(
        self: Window,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Window(title: \"{s}\", open: {any})", .{ self.title, self.open });
    }
};

pub const Components = .{
    Window,
};

fn init() !void {
    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
    if (imgui_docking) {
        ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    }
}

fn setupFrame() !void {
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
}

fn drawWindow(windowQuery: Query(struct { Window, BuiltinPlugin.Transform })) !void {
    for (windowQuery.entities) |entity| {
        if (!windowQuery.filter(entity)) continue;
        const window = windowQuery.getComponentMut(entity, Window);
        if (!window.open) continue;

        const transform = windowQuery.getComponentMut(entity, Transform);
        ig.igSetNextWindowPos(.{ .x = transform.x, .y = transform.y }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        if (ig.igBegin(window.title, &window.open, ig.ImGuiWindowFlags_None)) {
            const vec = ig.igGetWindowPos();
            transform.x = vec.x;
            transform.y = vec.y;
        }
        ig.igEnd();
    }
}

fn renderUi() !void {
    sokol.imgui.render();
}

fn deinit() !void {
    sokol.imgui.shutdown();
}

fn handleEvent(event: sokol.app.Event) !void {
    _ = sokol.imgui.handleEvent(event);
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerStartupSystem(init, .first);
    registry.registerSystem(setupFrame, .first);
    registry.registerSystem(drawWindow, .render);
    registry.registerSystem(renderUi, .render_submit);
    registry.registerTerminateSystem(deinit, .post_process);
    registry.registerEventHandler(handleEvent);
}

const std = @import("std");
