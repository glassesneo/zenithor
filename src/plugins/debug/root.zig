const StructField = std.builtin.Type;
const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const SingleTag = sparze.SingleTag;
const sokol = @import("sokol");
const imgui_docking = @import("build_options").docking;
pub const ig = if (imgui_docking) @import("cimgui_docking") else @import("cimgui");

const BuiltinPlugin = @import("../../core/builtin.zig");
const Transform = BuiltinPlugin.Transform;

const system_module = @import("../../core/system.zig");
const SystemRegistry = system_module.SystemRegistry;

/// Simple tag component for marking entities to be tracked in debug UI
pub const Tracked = struct {};

/// Debug state for tracking changes and UI preferences
const DebugState = struct {
    // Hash map to store previous component values (entity -> component hash)
    previous_values: std.AutoHashMap(u64, u64),
    // Hash map to track which components are visible
    component_visibility: std.AutoHashMap(u64, bool),
    // Global settings
    show_gizmos: bool = true,
    gizmo_size: f32 = 10.0,
    highlight_duration_frames: u32 = 60, // How long to highlight changes
    highlight_timers: std.AutoHashMap(u64, u32), // entity_component_hash -> frames remaining
};

var debug_state: DebugState = undefined;
var debug_state_initialized: bool = false;

fn initDebugState(allocator: std.mem.Allocator) !void {
    if (!debug_state_initialized) {
        debug_state = .{
            .previous_values = std.AutoHashMap(u64, u64).init(allocator),
            .component_visibility = std.AutoHashMap(u64, bool).init(allocator),
            .highlight_timers = std.AutoHashMap(u64, u32).init(allocator),
        };
        debug_state_initialized = true;
    }
}

fn deinitDebugState() void {
    if (debug_state_initialized) {
        debug_state.previous_values.deinit();
        debug_state.component_visibility.deinit();
        debug_state.highlight_timers.deinit();
        debug_state_initialized = false;
    }
}

/// Generate a hash for entity+component combination
fn getComponentKey(entity: sparze.Entity, comptime ComponentType: type) u64 {
    const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(ComponentType));
    return std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&entity));
}

/// Hash component data for change detection
fn hashComponentData(component: anytype) u64 {
    const bytes = std.mem.asBytes(&component);
    return std.hash.Wyhash.hash(0, bytes);
}

/// Check if component has changed since last frame
fn hasComponentChanged(entity: sparze.Entity, comptime ComponentType: type, component: *const ComponentType) !bool {
    const key = getComponentKey(entity, ComponentType);
    const current_hash = hashComponentData(component.*);

    if (debug_state.previous_values.get(key)) |prev_hash| {
        if (prev_hash != current_hash) {
            try debug_state.previous_values.put(key, current_hash);
            try debug_state.highlight_timers.put(key, debug_state.highlight_duration_frames);
            return true;
        }
        return false;
    } else {
        try debug_state.previous_values.put(key, current_hash);
        return false;
    }
}

/// Check if component should be highlighted (changed recently)
fn shouldHighlight(entity: sparze.Entity, comptime ComponentType: type) bool {
    const key = getComponentKey(entity, ComponentType);
    if (debug_state.highlight_timers.get(key)) |frames| {
        return frames > 0;
    }
    return false;
}

/// Update highlight timers (call each frame)
fn updateHighlightTimers() void {
    var it = debug_state.highlight_timers.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* > 0) {
            entry.value_ptr.* -= 1;
        }
    }
}

/// Check if component type is visible
fn isComponentVisible(comptime ComponentType: type) bool {
    const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(ComponentType));
    return debug_state.component_visibility.get(type_hash) orelse true; // Default to visible
}

/// Toggle component type visibility
fn toggleComponentVisibility(comptime ComponentType: type) !void {
    const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(ComponentType));
    const current = debug_state.component_visibility.get(type_hash) orelse true;
    try debug_state.component_visibility.put(type_hash, !current);
}

/// Draw gizmos for all tracked entities with Transform component
fn drawGizmos(commands: anytype, tracked_entities: []const sparze.Entity) !void {
    if (!debug_state.show_gizmos) return;

    const transform_sparse_set = commands.getSparseSetPtr(Transform);

    sokol.gl.beginPoints();
    sokol.gl.pointSize(debug_state.gizmo_size);

    for (tracked_entities) |entity| {
        if (transform_sparse_set.getPtr(entity)) |transform| {
            // Draw a bright magenta point at entity position
            sokol.gl.c4b(255, 0, 255, 255);
            sokol.gl.v2f(transform.x, transform.y);
        }
    }

    sokol.gl.end();

    // Draw cross-hair gizmo for each entity
    sokol.gl.beginLines();

    for (tracked_entities) |entity| {
        if (transform_sparse_set.getPtr(entity)) |transform| {
            const size = debug_state.gizmo_size;

            // Horizontal line
            sokol.gl.c4b(255, 255, 0, 200);
            sokol.gl.v2f(transform.x - size, transform.y);
            sokol.gl.v2f(transform.x + size, transform.y);

            // Vertical line
            sokol.gl.v2f(transform.x, transform.y - size);
            sokol.gl.v2f(transform.x, transform.y + size);
        }
    }

    sokol.gl.end();
}

/// Open a debug window showing all components of tracked entities
/// Usage: call this from a system with access to commands/world and the tracked entities query
pub fn openDebugWindow(ComponentTypes: anytype, commands: anytype, tracked_entities: []const sparze.Entity) !void {
    // Initialize debug state if needed
    if (!debug_state_initialized) {
        try initDebugState(std.heap.c_allocator);
    }

    // Update highlight timers
    updateHighlightTimers();

    const pos = ig.ImVec2{ .x = 10, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 500, .y = 600 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    const window_flags = ig.ImGuiWindowFlags_None;
    if (ig.igBegin("Entity Tracker", &window_open, window_flags)) {
        // Show count of tracked entities
        var header_buf: [128]u8 = undefined;
        const header_text = std.fmt.bufPrintZ(&header_buf, "Tracking {d} {s}", .{ tracked_entities.len, if (tracked_entities.len == 1) "Entity" else "Entities" }) catch "Tracking Entities";

        ig.igTextColored(.{ .x = 0.2, .y = 0.8, .z = 1.0, .w = 1.0 }, "%s", header_text.ptr);

        // Gizmo controls
        ig.igSameLine();
        if (ig.igSmallButton("Gizmos")) {
            debug_state.show_gizmos = !debug_state.show_gizmos;
        }
        if (ig.igIsItemHovered(ig.ImGuiHoveredFlags_None)) {
            ig.igSetTooltip("%s", if (debug_state.show_gizmos) "Hide Gizmos" else "Show Gizmos");
        }

        ig.igSeparator();

        // Component visibility controls
        if (ig.igCollapsingHeader("Component Filters", ig.ImGuiTreeNodeFlags_None)) {
            ig.igText("%s", "Show/Hide Components:");
            ig.igSpacing();

            inline for (ComponentTypes) |C| {
                const type_name = @typeName(C);
                const short_name = blk: {
                    var i: usize = type_name.len;
                    while (i > 0) : (i -= 1) {
                        if (type_name[i - 1] == '.') break;
                    }
                    break :blk type_name[i..];
                };

                var visible = isComponentVisible(C);
                var checkbox_label: [128]u8 = undefined;
                const label = std.fmt.bufPrintZ(&checkbox_label, "{s}###{s}", .{ short_name, type_name }) catch short_name;

                if (ig.igCheckbox(label.ptr, &visible)) {
                    try toggleComponentVisibility(C);
                }

                if ((std.meta.fields(@TypeOf(ComponentTypes)).len + 1) > 1) {
                    ig.igSameLine();
                }
            }
            ig.igSpacing();
            ig.igSeparator();
        }

        ig.igSpacing();

        // Iterate through all tracked entities
        for (tracked_entities, 0..) |entity, entity_idx| {
            // Add separator between entities (but not before the first one)
            if (entity_idx > 0) {
                ig.igSpacing();
                ig.igSpacing();
                ig.igSeparator();
                ig.igSeparator();
                ig.igSpacing();
            }

            // Entity header
            var entity_buf: [128]u8 = undefined;
            const entity_text = std.fmt.bufPrintZ(&entity_buf, "Entity ID: {d}", .{entity}) catch "Entity: <error>";

            // Make it a collapsible header for each entity
            const entity_header_flags = ig.ImGuiTreeNodeFlags_DefaultOpen |
                ig.ImGuiTreeNodeFlags_Framed |
                ig.ImGuiTreeNodeFlags_SpanAvailWidth;

            ig.igPushStyleColorImVec4(ig.ImGuiCol_Header, .{ .x = 0.15, .y = 0.4, .z = 0.6, .w = 0.8 });
            ig.igPushStyleColorImVec4(ig.ImGuiCol_HeaderHovered, .{ .x = 0.2, .y = 0.5, .z = 0.7, .w = 0.9 });
            ig.igPushStyleColorImVec4(ig.ImGuiCol_HeaderActive, .{ .x = 0.25, .y = 0.6, .z = 0.8, .w = 1.0 });

            const entity_node_open = ig.igCollapsingHeader(entity_text.ptr, entity_header_flags);

            ig.igPopStyleColor();
            ig.igPopStyleColor();
            ig.igPopStyleColor();

            if (!entity_node_open) continue;

            ig.igSpacing();

            // Iterate through all component types and display them if entity has them
            var component_count: usize = 0;
            inline for (ComponentTypes ++ .{Tracked}) |C| {
                // Try to get the component - if it exists, display it
                const sparse_set = commands.getSparseSetPtr(C);
                if (sparse_set.getPtr(entity)) |component| {
                    component_count += 1;

                    // Skip rendering if component type is hidden
                    if (isComponentVisible(C)) {

                        // Check for changes
                        _ = if (@sizeOf(C) > 0)
                            try hasComponentChanged(entity, C, component)
                        else
                            false;

                        const is_highlighted = shouldHighlight(entity, C);

                        // Component name with tree node for collapsible sections
                        const type_name = @typeName(C);
                        const short_name = blk: {
                            // Extract just the component name (after last '.')
                            var i: usize = type_name.len;
                            while (i > 0) : (i -= 1) {
                                if (type_name[i - 1] == '.') break;
                            }
                            break :blk type_name[i..];
                        };

                        var name_buf: [256]u8 = undefined;
                        const node_label = std.fmt.bufPrintZ(&name_buf, "{s}{s}###{d}_{d}", .{ short_name, if (is_highlighted) " *" else "", entity_idx, component_count }) catch "Component";

                        const tree_flags = ig.ImGuiTreeNodeFlags_DefaultOpen |
                            ig.ImGuiTreeNodeFlags_Framed |
                            ig.ImGuiTreeNodeFlags_SpanAvailWidth;

                        // Highlight the tree node header if changed
                        if (is_highlighted) {
                            ig.igPushStyleColorImVec4(ig.ImGuiCol_Header, .{ .x = 0.6, .y = 0.3, .z = 0.1, .w = 0.8 });
                            ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 1.0, .y = 0.8, .z = 0.3, .w = 1.0 });
                        }

                        if (ig.igTreeNodeExPtr(@ptrCast(component), tree_flags, "%s", node_label.ptr)) {
                            if (is_highlighted) {
                                ig.igPopStyleColor();
                                ig.igPopStyleColor();
                            }

                            ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 });

                            // Full type path in smaller text
                            var path_buf: [512]u8 = undefined;
                            const type_path = std.fmt.bufPrintZ(&path_buf, "Type: {s}", .{type_name}) catch "Type: <error>";
                            ig.igTextWrapped("%s", type_path.ptr);

                            ig.igPopStyleColor();
                            ig.igSpacing();

                            // Display component value
                            if (@sizeOf(C) > 0) {
                                var value_buf: [2048]u8 = undefined;
                                const value_text = if (std.meta.hasMethod(C, "format"))
                                    std.fmt.bufPrintZ(&value_buf, "{f}", .{component.*}) catch "<format error>"
                                else
                                    std.fmt.bufPrintZ(&value_buf, "{any}", .{component.*}) catch "<format error>";

                                // Use brighter color if highlighted
                                const text_color = if (is_highlighted)
                                    ig.ImVec4{ .x = 1.0, .y = 0.9, .z = 0.4, .w = 1.0 }
                                else
                                    ig.ImVec4{ .x = 1.0, .y = 1.0, .z = 0.8, .w = 1.0 };

                                ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, text_color);
                                ig.igTextWrapped("%s", value_text.ptr);
                                ig.igPopStyleColor();
                            } else {
                                ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 });
                                ig.igText("%s", "<tag component>");
                                ig.igPopStyleColor();
                            }

                            ig.igTreePop();
                        } else if (is_highlighted) {
                            ig.igPopStyleColor();
                            ig.igPopStyleColor();
                        }
                        ig.igSpacing();
                    }
                }
            }

            // Footer with component count for this entity
            ig.igSpacing();
            var count_buf: [64]u8 = undefined;
            const count_text = std.fmt.bufPrintZ(&count_buf, "Components: {d}", .{component_count}) catch "Components: ?";
            ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.5, .y = 0.8, .z = 0.5, .w = 1.0 });
            ig.igText("%s", count_text.ptr);
            ig.igPopStyleColor();
        }
    }
    ig.igEnd();

    // Draw gizmos in the world
    try drawGizmos(commands, tracked_entities);
}

pub const Components = .{Tracked};

pub fn build(registry: SystemRegistry) !void {
    registry.registerTerminateSystem(cleanup, .last);
}

fn cleanup() !void {
    deinitDebugState();
}

const std = @import("std");
