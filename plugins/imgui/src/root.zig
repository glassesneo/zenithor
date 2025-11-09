const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");
const imgui_docking = @import("build_options").docking;
pub const ig = if (imgui_docking) @import("cimgui_docking") else @import("cimgui");

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const SystemRegistry = zenithor.SystemRegistry;

pub const Window = struct {
    title: [256:0]u8 = [_:0]u8{0} ** 256,
    title_len: usize = 0,
    open: bool = true,

    pub fn init(title: [:0]const u8) Window {
        var window = Window{};
        const len = @min(title.len, 255);
        @memcpy(window.title[0..len], title[0..len]);
        window.title[len] = 0;
        window.title_len = len;
        return window;
    }

    pub fn getTitle(self: *const Window) [:0]const u8 {
        return self.title[0..self.title_len :0];
    }

    pub fn format(
        self: Window,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Window(title: \"{s}\", open: {any})", .{ self.getTitle(), self.open });
    }
};

pub const Components = .{
    Window,
};

pub const Events = .{};

// Note: sokol.imgui is initialized centrally in src/core/application.zig
// Docking is enabled there if -Dimgui-docking build flag is set

fn setupFrame() !void {
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
}

fn drawWindow(windowQuery: Query(struct { Window, Transform })) !void {
    for (windowQuery.entities) |entity| {
        if (!windowQuery.filter(entity)) continue;
        const window = windowQuery.getComponentMut(entity, Window);
        if (!window.open) continue;

        const transform = windowQuery.getComponentMut(entity, Transform);
        ig.igSetNextWindowPos(.{ .x = transform.x, .y = transform.y }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        if (ig.igBegin(&window.title, &window.open, ig.ImGuiWindowFlags_None)) {
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

// Note: sokol.imgui shutdown is handled centrally in src/core/application.zig

fn handleEvent(event: sokol.app.Event) !void {
    _ = sokol.imgui.handleEvent(event);
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerSystem(setupFrame, .first);
    registry.registerSystem(drawWindow, .render);
    registry.registerSystem(renderUi, .render_submit);
    registry.registerEventHandler(handleEvent);
}

const std = @import("std");