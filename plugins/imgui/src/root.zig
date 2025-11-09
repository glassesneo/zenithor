const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");
const imgui_docking = @import("build_options").docking;
pub const ig = if (imgui_docking) @import("cimgui_docking") else @import("cimgui");

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const SystemRegistry = zenithor.SystemRegistry;

pub const Components = .{
    // Empty - no components needed for ImGui plugin itself
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

// New function to allow ECS-based UI rendering
pub fn begin(name: [:0]const u8, open: ?*bool, flags: c_int) bool {
    return ig.igBegin(name, open, @intCast(flags));
}

pub fn end() void {
    ig.igEnd();
}

pub fn text(text_content: [:0]const u8) void {
    ig.igText("%s", text_content.ptr);
}

pub fn textFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const formatted_text = std.fmt.bufPrintZ(&buf, fmt, args) catch "Error";
    ig.igText("%s", formatted_text.ptr);
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
    registry.registerSystem(renderUi, .render_submit);
    registry.registerEventHandler(handleEvent);
}

const std = @import("std");

