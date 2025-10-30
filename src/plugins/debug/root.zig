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

/// Entity lifecycle event for logging
const LifecycleEvent = struct {
    entity: sparze.Entity,
    event_type: enum { created, destroyed },
    frame_number: u64,
    timestamp: f64, // seconds since start
};

/// Performance metrics tracking
const PerformanceMetrics = struct {
    frame_times: [120]f32 = [_]f32{0.0} ** 120, // Last 120 frames (2 seconds at 60fps)
    frame_index: usize = 0,
    current_fps: f32 = 0.0,
    min_fps: f32 = 999.0,
    max_fps: f32 = 0.0,
    avg_frame_time_ms: f32 = 0.0,
    last_frame_time: u64 = 0,
};

const STABLE_FPS_WARMUP_FRAMES: u64 = 60;

/// Debug state for tracking changes and UI preferences
const DebugState = struct {
    // Hash map to store previous component values (entity -> component hash)
    previous_values: std.AutoHashMap(u64, u64),
    // Hash map to track which components are visible
    component_visibility: std.AutoHashMap(u64, bool),
    // Global settings
    show_gizmos: bool = true,
    show_entity_ids: bool = true,
    show_entity_versions: bool = false,
    gizmo_size: f32 = 10.0,
    highlight_duration_frames: u32 = 60, // How long to highlight changes
    highlight_timers: std.AutoHashMap(u64, u32), // entity_component_hash -> frames remaining

    // Performance metrics
    performance: PerformanceMetrics = .{},
    show_performance_window: bool = true,

    // Entity lifecycle log
    lifecycle_log: std.ArrayListUnmanaged(LifecycleEvent) = .{},
    allocator: std.mem.Allocator = undefined,
    show_lifecycle_window: bool = true,
    frame_counter: u64 = 0,
    start_time: f64 = 0.0,

    // Entity tracking
    tracked_entity_count: usize = 0,
    total_entity_count: usize = 0,
};

var debug_state: DebugState = undefined;
var debug_state_initialized: bool = false;

fn initDebugState(allocator: std.mem.Allocator) !void {
    if (!debug_state_initialized) {
        debug_state = .{
            .previous_values = std.AutoHashMap(u64, u64).init(allocator),
            .component_visibility = std.AutoHashMap(u64, bool).init(allocator),
            .highlight_timers = std.AutoHashMap(u64, u32).init(allocator),
            .allocator = allocator,
        };
        debug_state.start_time = sokol.time.sec(sokol.time.now());
        sokol.time.setup();
        debug_state_initialized = true;
    }
}

fn deinitDebugState() void {
    if (debug_state_initialized) {
        debug_state.previous_values.deinit();
        debug_state.component_visibility.deinit();
        debug_state.highlight_timers.deinit();
        debug_state.lifecycle_log.deinit(debug_state.allocator);
        debug_state_initialized = false;
    }
}

/// Update performance metrics each frame
fn updatePerformanceMetrics() void {
    const now = sokol.time.now();

    if (debug_state.performance.last_frame_time != 0) {
        const frame_ticks = now - debug_state.performance.last_frame_time;
        const frame_time = sokol.time.sec(frame_ticks);
        const frame_time_ms = @as(f32, @floatCast(frame_time * 1000.0));

        // Store frame time in ring buffer
        debug_state.performance.frame_times[debug_state.performance.frame_index] = frame_time_ms;
        debug_state.performance.frame_index = (debug_state.performance.frame_index + 1) % debug_state.performance.frame_times.len;

        // Calculate FPS
        if (frame_time > 0.0001) {
            debug_state.performance.current_fps = @floatCast(1.0 / frame_time);

            // Update min/max only after warmup frames have passed
            if (debug_state.frame_counter >= STABLE_FPS_WARMUP_FRAMES) {
                if (debug_state.performance.current_fps < debug_state.performance.min_fps) {
                    debug_state.performance.min_fps = debug_state.performance.current_fps;
                }
                if (debug_state.performance.current_fps > debug_state.performance.max_fps) {
                    debug_state.performance.max_fps = debug_state.performance.current_fps;
                }
            }
        }

        // Calculate average frame time
        var sum: f32 = 0.0;
        for (debug_state.performance.frame_times) |ft| {
            sum += ft;
        }
        debug_state.performance.avg_frame_time_ms = sum / @as(f32, @floatFromInt(debug_state.performance.frame_times.len));
    }

    debug_state.performance.last_frame_time = now;
    debug_state.frame_counter += 1;
}

/// Log entity creation
pub fn logEntityCreated(entity: sparze.Entity) !void {
    if (!debug_state_initialized) return;

    const event = LifecycleEvent{
        .entity = entity,
        .event_type = .created,
        .frame_number = debug_state.frame_counter,
        .timestamp = sokol.time.sec(sokol.time.now()) - debug_state.start_time,
    };

    try debug_state.lifecycle_log.append(debug_state.allocator, event);

    // Keep log size manageable (last 1000 events)
    if (debug_state.lifecycle_log.items.len > 1000) {
        _ = debug_state.lifecycle_log.orderedRemove(0);
    }
}

/// Log entity destruction
pub fn logEntityDestroyed(entity: sparze.Entity) !void {
    if (!debug_state_initialized) return;

    const event = LifecycleEvent{
        .entity = entity,
        .event_type = .destroyed,
        .frame_number = debug_state.frame_counter,
        .timestamp = sokol.time.sec(sokol.time.now()) - debug_state.start_time,
    };

    try debug_state.lifecycle_log.append(debug_state.allocator, event);

    // Keep log size manageable
    if (debug_state.lifecycle_log.items.len > 1000) {
        _ = debug_state.lifecycle_log.orderedRemove(0);
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
/// Displays entity index next to gizmo (e.g., "42" or "42:v1" if version shown)
fn drawGizmos(commands: anytype, tracked_entities: []const sparze.Entity) !void {
    if (!debug_state.show_gizmos) return;

    const transform_sparse_set = commands.getSparseSetPtr(Transform);

    sokol.gl.beginPoints();
    sokol.gl.pointSize(debug_state.gizmo_size);

    for (tracked_entities) |entity| {
        if (transform_sparse_set.getPtr(entity)) |transform| {
            // Draw a bright magenta point at entity position
            sokol.gl.c4b(255, 0, 255, 255);
            sokol.gl.v3f(transform.x, transform.y, transform.z);
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
            sokol.gl.v3f(transform.x - size, transform.y, transform.z);
            sokol.gl.v3f(transform.x + size, transform.y, transform.z);

            // Vertical line
            sokol.gl.v3f(transform.x, transform.y - size, transform.z);
            sokol.gl.v3f(transform.x, transform.y + size, transform.z);
        }
    }

    sokol.gl.end();

    // Draw entity IDs using ImGui background draw list so labels render
    // underneath ImGui windows (match the gizmo which is rendered beneath UI)
    if (!debug_state.show_entity_ids) return;

    const draw_list = ig.igGetBackgroundDrawList();

    for (tracked_entities) |entity| {
        const transform = transform_sparse_set.getPtr(entity) orelse continue;
        // Format entity ID - show index, optionally with version
        var id_buf: [32]u8 = undefined;
        const entity_index = sparze.getIndex(entity);
        const entity_version = sparze.getVersion(entity);

        const id_text = if (debug_state.show_entity_versions)
            std.fmt.bufPrintZ(&id_buf, "{d}:v{d}", .{ entity_index, entity_version }) catch "?"
        else
            std.fmt.bufPrintZ(&id_buf, "{d}", .{entity_index}) catch "?";

        // Position text slightly offset from entity
        const text_offset_x = debug_state.gizmo_size + 5.0;
        const text_offset_y = -debug_state.gizmo_size - 5.0;
        const text_pos = ig.ImVec2{ .x = transform.x + text_offset_x, .y = transform.y + text_offset_y };

        // Draw text with background for readability
        const text_color = ig.igGetColorU32ImVec4(.{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 }); // Yellow
        const bg_color = ig.igGetColorU32ImVec4(.{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.7 }); // Semi-transparent black

        // Calculate text size for background
        const text_size = ig.igCalcTextSize(id_text.ptr);
        const padding = 2.0;

        // Draw background rectangle
        const bg_min = ig.ImVec2{ .x = text_pos.x - padding, .y = text_pos.y - padding };
        const bg_max = ig.ImVec2{ .x = text_pos.x + text_size.x + padding, .y = text_pos.y + text_size.y + padding };
        ig.ImDrawList_AddRectFilled(draw_list, bg_min, bg_max, bg_color);

        // Draw text
        ig.ImDrawList_AddText(draw_list, text_pos, text_color, id_text.ptr);
    }
}

/// Open a debug window showing all components of tracked entities
///
/// Features:
/// - Component inspector with change highlighting
/// - Entity gizmos (crosshair markers at entity positions)
/// - Entity ID labels (shows entity index, e.g., "42" or "42:v1" with version)
///
/// Usage: call this from a system with access to commands/world and the tracked entities query
pub fn openDebugWindow(ComponentTypes: anytype, commands: anytype, tracked_entities: []const sparze.Entity) !void {
    // Initialize debug state if needed
    if (!debug_state_initialized) {
        try initDebugState(std.heap.c_allocator);
    }

    // Update tracked entity count
    debug_state.tracked_entity_count = tracked_entities.len;

    // Update highlight timers
    updateHighlightTimers();

    const pos = ig.ImVec2{ .x = 10, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 420, .y = 700 };
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

        ig.igSameLine();
        if (ig.igSmallButton("IDs")) {
            debug_state.show_entity_ids = !debug_state.show_entity_ids;
        }
        if (ig.igIsItemHovered(ig.ImGuiHoveredFlags_None)) {
            ig.igSetTooltip("%s", if (debug_state.show_entity_ids) "Hide Entity IDs" else "Show Entity IDs");
        }

        ig.igSameLine();
        if (ig.igSmallButton("Ver")) {
            debug_state.show_entity_versions = !debug_state.show_entity_versions;
        }
        if (ig.igIsItemHovered(ig.ImGuiHoveredFlags_None)) {
            ig.igSetTooltip("%s", if (debug_state.show_entity_versions) "Hide Versions" else "Show Versions");
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
            const entity_index = sparze.getIndex(entity);
            const entity_version = sparze.getVersion(entity);
            const entity_text = std.fmt.bufPrintZ(&entity_buf, "Entity {d} (v{d})", .{ entity_index, entity_version }) catch "Entity: <error>";

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

/// Open performance metrics window
pub fn openPerformanceWindow() void {
    if (!debug_state.show_performance_window) return;

    const pos = ig.ImVec2{ .x = 440, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 350, .y = 250 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    if (ig.igBegin("Performance Metrics", &debug_state.show_performance_window, ig.ImGuiWindowFlags_None)) {
        const perf = &debug_state.performance;

        // FPS Display
        ig.igText("FPS:");
        ig.igSameLine();
        var fps_buf: [32]u8 = undefined;
        const fps_text = std.fmt.bufPrintZ(&fps_buf, "{d:.1}", .{perf.current_fps}) catch "N/A";
        ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.2, .y = 1.0, .z = 0.4, .w = 1.0 });
        ig.igText("%s", fps_text.ptr);
        ig.igPopStyleColor();

        // Frame Time
        ig.igText("Frame Time:");
        ig.igSameLine();
        var ft_buf: [32]u8 = undefined;
        const ft_text = std.fmt.bufPrintZ(&ft_buf, "{d:.2} ms", .{perf.avg_frame_time_ms}) catch "N/A";
        ig.igText("%s", ft_text.ptr);

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // Min/Max FPS (show N/A during initial warmup frames)
        ig.igText("Min FPS:");
        ig.igSameLine();
        var min_buf: [32]u8 = undefined;
        const min_text = if (debug_state.frame_counter < STABLE_FPS_WARMUP_FRAMES)
            std.fmt.bufPrintZ(&min_buf, "N/A", .{}) catch "N/A"
        else
            std.fmt.bufPrintZ(&min_buf, "{d:.1}", .{perf.min_fps}) catch "N/A";
        ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 1.0, .y = 0.5, .z = 0.3, .w = 1.0 });
        ig.igText("%s", min_text.ptr);
        ig.igPopStyleColor();

        ig.igText("Max FPS:");
        ig.igSameLine();
        var max_buf: [32]u8 = undefined;
        const max_text = if (debug_state.frame_counter < STABLE_FPS_WARMUP_FRAMES)
            std.fmt.bufPrintZ(&max_buf, "N/A", .{}) catch "N/A"
        else
            std.fmt.bufPrintZ(&max_buf, "{d:.1}", .{perf.max_fps}) catch "N/A";
        ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.3, .y = 0.8, .z = 1.0, .w = 1.0 });
        ig.igText("%s", max_text.ptr);
        ig.igPopStyleColor();

        if (ig.igButton("Reset Min/Max")) {
            perf.min_fps = perf.current_fps;
            perf.max_fps = perf.current_fps;
        }

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // Frame time graph
        ig.igText("Frame Time History:");
        ig.igPlotLines("##frametime", &perf.frame_times, @intCast(perf.frame_times.len));

        ig.igSpacing();

        // Entity counts
        ig.igText("Tracked Entities:");
        ig.igSameLine();
        var tracked_buf: [32]u8 = undefined;
        const tracked_text = std.fmt.bufPrintZ(&tracked_buf, "{d}", .{debug_state.tracked_entity_count}) catch "?";
        ig.igText("%s", tracked_text.ptr);

        ig.igText("Total Events:");
        ig.igSameLine();
        var events_buf: [32]u8 = undefined;
        const events_text = std.fmt.bufPrintZ(&events_buf, "{d}", .{debug_state.lifecycle_log.items.len}) catch "?";
        ig.igText("%s", events_text.ptr);

        ig.igSpacing();
        ig.igText("Frame:");
        ig.igSameLine();
        var frame_buf: [32]u8 = undefined;
        const frame_text = std.fmt.bufPrintZ(&frame_buf, "{d}", .{debug_state.frame_counter}) catch "?";
        ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, .{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 });
        ig.igText("%s", frame_text.ptr);
        ig.igPopStyleColor();
    }
    ig.igEnd();
}

/// Open entity lifecycle log window
pub fn openLifecycleWindow() void {
    if (!debug_state.show_lifecycle_window) return;

    const pos = ig.ImVec2{ .x = 440, .y = 270 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 350, .y = 520 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    if (ig.igBegin("Entity Lifecycle Log", &debug_state.show_lifecycle_window, ig.ImGuiWindowFlags_None)) {
        var header_buf: [64]u8 = undefined;
        const header_text = std.fmt.bufPrintZ(&header_buf, "Events: {d}", .{debug_state.lifecycle_log.items.len}) catch "Events";
        ig.igTextColored(.{ .x = 0.2, .y = 0.8, .z = 1.0, .w = 1.0 }, "%s", header_text.ptr);

        ig.igSameLine();
        if (ig.igSmallButton("Clear")) {
            debug_state.lifecycle_log.clearRetainingCapacity();
        }

        ig.igSeparator();
        ig.igSpacing();

        // Statistics
        var created_count: usize = 0;
        var destroyed_count: usize = 0;
        for (debug_state.lifecycle_log.items) |event| {
            switch (event.event_type) {
                .created => created_count += 1,
                .destroyed => destroyed_count += 1,
            }
        }

        var stats_buf: [128]u8 = undefined;
        const stats_text = std.fmt.bufPrintZ(&stats_buf, "Created: {d}  |  Destroyed: {d}  |  Net: {d}", .{
            created_count,
            destroyed_count,
            created_count -| destroyed_count,
        }) catch "Stats";
        ig.igText("%s", stats_text.ptr);

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // Event log (reverse chronological - newest first)
        _ = ig.igBeginChild("EventLog", .{ .x = 0, .y = 0 }, ig.ImGuiChildFlags_Border, ig.ImGuiWindowFlags_None);

        var i: usize = debug_state.lifecycle_log.items.len;
        while (i > 0) {
            i -= 1;
            const event = debug_state.lifecycle_log.items[i];

            var event_buf: [256]u8 = undefined;
            const event_type_str = switch (event.event_type) {
                .created => "CREATED",
                .destroyed => "DESTROYED",
            };

            const event_entity_index = sparze.getIndex(event.entity);
            const event_entity_version = sparze.getVersion(event.entity);
            const event_text = std.fmt.bufPrintZ(&event_buf, "[{d:5.2}s] Frame {d:6} | Entity {d} (v{d}) {s}", .{
                event.timestamp,
                event.frame_number,
                event_entity_index,
                event_entity_version,
                event_type_str,
            }) catch "Event";

            // Color code by event type
            const color = switch (event.event_type) {
                .created => ig.ImVec4{ .x = 0.3, .y = 1.0, .z = 0.5, .w = 1.0 },
                .destroyed => ig.ImVec4{ .x = 1.0, .y = 0.4, .z = 0.3, .w = 1.0 },
            };

            ig.igPushStyleColorImVec4(ig.ImGuiCol_Text, color);
            ig.igText("%s", event_text.ptr);
            ig.igPopStyleColor();
        }

        // Auto-scroll to bottom (newest)
        if (ig.igGetScrollY() >= ig.igGetScrollMaxY()) {
            ig.igSetScrollHereY(1.0);
        }

        ig.igEndChild();
    }
    ig.igEnd();
}

pub const Components = .{
    Tracked,
};

pub const Events = .{};

pub fn build(registry: SystemRegistry) !void {
    registry.registerSystem(updateDebugSystems, .first);
    registry.registerTerminateSystem(cleanup, .last);
}

fn updateDebugSystems() !void {
    updatePerformanceMetrics();
    openPerformanceWindow();
    openLifecycleWindow();
}

fn cleanup() !void {
    deinitDebugState();
}

const std = @import("std");
