const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");
const imgui_docking = @import("build_options").docking;
pub const ig = if (imgui_docking) @import("cimgui_docking") else @import("cimgui");

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const SystemRegistry = zenithor.SystemRegistry;

pub const Components = .{};
pub const Events = .{};

pub const ImVec2 = ig.ImVec2;
pub const ImVec4 = ig.ImVec4;

// Window position/size conditions
pub const ImGuiCond = enum(c_int) {
    Never = 0, // Never set the position/size
    Always = 1, // Set every frame
    Once = 2, // Set on the first call (per window)
    FirstUseEver = 4, // Set if the window has no saved data (if doesn't exist in .ini file)
    Appearing = 8, // Set on the first call for a window that just appeared
};

// Window flags
pub const ImGuiWindowFlags = enum(c_int) {
    None = 0,
    NoTitleBar = 1,
    NoResize = 2,
    NoMove = 4,
    NoScrollbar = 8,
    NoScrollWithMouse = 16,
    NoCollapse = 32,
    AlwaysAutoResize = 64,
    NoBackground = 128,
    NoSavedSettings = 256,
    NoMouseInputs = 512,
    MenuBar = 1024,
    HorizontalScrollbar = 2048,
    NoFocusOnAppearing = 4096,
    NoBringToFrontOnFocus = 8192,
    AlwaysVerticalScrollbar = 16384,
    AlwaysHorizontalScrollbar = 32768,
    AlwaysUseWindowPadding = 65536,
    NoNavInputs = 262144,
    NoNavFocus = 524288,
    UnsavedDocument = 1048576,
    NoNav = 786432,
    NoDecoration = 41,
    NoInputs = 793,
};

pub fn begin(name: [:0]const u8, open: ?*bool, flags: ImGuiWindowFlags) bool {
    return ig.igBegin(name, open, @intFromEnum(flags));
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

pub fn textColored(color: ImVec4, text_content: [:0]const u8) void {
    ig.igTextColored(color, "%s", text_content.ptr);
}

pub fn textColoredFmt(color: ImVec4, comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const formatted_text = std.fmt.bufPrintZ(&buf, fmt, args) catch "Error";
    ig.igTextColored(color, "%s", formatted_text.ptr);
}

pub fn setNextWindowPos(pos: ImVec2, cond: ImGuiCond) void {
    ig.igSetNextWindowPos(pos, @intFromEnum(cond));
}

pub fn setNextWindowSize(size: ImVec2, cond: ImGuiCond) void {
    ig.igSetNextWindowSize(size, @intFromEnum(cond));
}

pub fn separator() void {
    ig.igSeparator();
}

pub fn spacing() void {
    ig.igSpacing();
}

pub fn sameLine() void {
    ig.igSameLine();
}

pub fn indent() void {
    ig.igIndent();
}

pub fn unindent() void {
    ig.igUnindent();
}

pub fn bulletText(text_content: [:0]const u8) void {
    ig.igBulletText("%s", text_content.ptr);
}

pub fn bulletTextFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const formatted_text = std.fmt.bufPrintZ(&buf, fmt, args) catch "Error";
    ig.igBulletText("%s", formatted_text.ptr);
}

pub fn button(label: [:0]const u8) bool {
    return ig.igButton(label);
}

pub fn buttonSize(label: [:0]const u8, size: ImVec2) bool {
    _ = size;
    return ig.igButton(label);
}

pub fn sliderFloat(label: [:0]const u8, value: *f32, min: f32, max: f32) bool {
    return ig.igSliderFloat(label, value, min, max);
}

pub fn sliderInt(label: [:0]const u8, value: *i32, min: i32, max: i32) bool {
    return ig.igSliderInt(label, value, min, max);
}

pub fn textWrapped(text_content: [:0]const u8) void {
    ig.igTextWrapped("%s", text_content.ptr);
}

fn setupFrame() !void {
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
}

fn renderUi() !void {
    sokol.imgui.render();
}

fn handleEvent(event: sokol.app.Event) !void {
    _ = sokol.imgui.handleEvent(event);
}

pub fn build(registry: SystemRegistry) !void {
    registry.registerStartupSystem(init, .first);
    registry.registerSystem(setupFrame, .first);
    registry.registerSystem(renderUi, .render_submit);
    registry.registerEventHandler(handleEvent);
}

fn init() !void {
    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
    if (imgui_docking) {
        ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    }
}

const std = @import("std");
