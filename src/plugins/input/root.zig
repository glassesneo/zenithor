const std = @import("std");
const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const sokol = @import("sokol");

const BuiltinPlugin = @import("../../core/builtin.zig");
const ImGuiPlugin = @import("../imgui/root.zig");
const ig = ImGuiPlugin.ig;

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

/// Mouse input resource containing mouse position and button states
pub const Mouse = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    left_button: bool = false,
    right_button: bool = false,
    middle_button: bool = false,
};

pub const Components = .{};
pub const Resources = .{Mouse};

// Internal storage for event-based input (before ImGui is ready)
var temp_mouse_x: f32 = 0.0;
var temp_mouse_y: f32 = 0.0;

fn handleEvent(event: sokol.app.Event) !void {
    // Capture mouse events before ImGui is ready
    switch (event.type) {
        .MOUSE_MOVE => {
            temp_mouse_x = event.mouse_x;
            temp_mouse_y = event.mouse_y;
        },
        else => {},
    }
}

fn updateMouse(mouse: sparze.Resource(Mouse)) !void {
    // Try to use ImGui IO if available, otherwise use temp storage
    const io = ig.igGetIO();
    if (io != null) {
        mouse.value.x = io.*.MousePos.x;
        mouse.value.y = io.*.MousePos.y;
        mouse.value.left_button = io.*.MouseDown[0];
        mouse.value.right_button = io.*.MouseDown[1];
        mouse.value.middle_button = io.*.MouseDown[2];
    } else {
        // Fallback to event-based tracking
        mouse.value.x = temp_mouse_x;
        mouse.value.y = temp_mouse_y;
    }
}

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Initialize Mouse resource with default values
    try world.setResource(Mouse, .{});

    // Register event handler for fallback input
    registry.registerEventHandler(handleEvent);

    // Register system to update mouse resource from ImGui IO
    registry.registerSystem(updateMouse, .first);
}
