const std = @import("std");
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;
const ImGuiPlugin = @import("imgui_plugin");
const TimePlugin = @import("time_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, TimePlugin, ErrorDemoPlugin }, .{});
}

const ErrorDemoPlugin = struct {
    pub const Components = .{};
    pub const Resources = .{
        ErrorLog,
        ErrorConfig,
    };
    pub const Events = .{
        BuiltinPlugin.GameLoopError,
        BuiltinPlugin.EventLoopError,
    };

    fn init(commands: anytype) !void {
        commands.setResource(ErrorLog, ErrorLog.init());
        commands.setResource(ErrorConfig, ErrorConfig{
            .trigger_system_error = false,
            .error_count = 0,
        });
    }

    pub const systems = .{
        .startup = &.{
            .{ .system = init, .stage = .first },
        },
        .main = &.{
            .{ .system = errorProneSystem, .stage = .update },
            .{ .system = errorMonitorSystem, .stage = .post_update },
            .{ .system = errorDisplaySystem, .stage = .render },
        },
    };
};

/// Resource to store caught errors for display
const ErrorLog = struct {
    const MAX_ERRORS = 50;
    const ErrorType = enum { game_loop, event_loop };
    const ErrorEntry = struct {
        error_type: ErrorType,
        error_name: []const u8,
        timestamp: f64,
    };

    entries: [MAX_ERRORS]ErrorEntry,
    count: usize,

    fn init() ErrorLog {
        return .{
            .entries = undefined,
            .count = 0,
        };
    }

    fn addError(self: *ErrorLog, error_type: ErrorType, err: anyerror, timestamp: f64) void {
        // If buffer is full, remove oldest entry
        if (self.count >= MAX_ERRORS) {
            // Shift all entries left
            for (1..self.count) |i| {
                self.entries[i - 1] = self.entries[i];
            }
            self.count -= 1;
        }

        self.entries[self.count] = .{
            .error_type = error_type,
            .error_name = @errorName(err),
            .timestamp = timestamp,
        };
        self.count += 1;
    }

    fn clear(self: *ErrorLog) void {
        self.count = 0;
    }

    fn slice(self: *const ErrorLog) []const ErrorEntry {
        return self.entries[0..self.count];
    }
};

/// Configuration for triggering test errors
const ErrorConfig = struct {
    trigger_system_error: bool,
    error_count: u32,
};

/// System that can intentionally fail for demonstration
fn errorProneSystem(config: zenithor.ResourceMut(ErrorConfig)) !void {
    if (config.value.trigger_system_error) {
        // Reset the flag before triggering error
        config.value.trigger_system_error = false;
        // Simulate an allocation failure or other error
        return error.DemoError;
    }
}

/// System that monitors error events and logs them
fn errorMonitorSystem(
    game_loop_errors: zenithor.EventReader(BuiltinPlugin.GameLoopError),
    event_loop_errors: zenithor.EventReader(BuiltinPlugin.EventLoopError),
    log: zenithor.ResourceMut(ErrorLog),
    time: zenithor.Resource(TimePlugin.Time),
    config: zenithor.ResourceMut(ErrorConfig),
) void {
    const timestamp = time.value.total_time;

    // Check for game loop errors
    for (game_loop_errors.queue) |err_event| {
        log.value.addError(.game_loop, err_event.err, timestamp);
        config.value.error_count += 1;
    }

    // Check for event loop errors
    for (event_loop_errors.queue) |err_event| {
        log.value.addError(.event_loop, err_event.err, timestamp);
        config.value.error_count += 1;
    }
}

/// System that displays error information using ImGui
fn errorDisplaySystem(
    log: zenithor.ResourceMut(ErrorLog),
    config: zenithor.ResourceMut(ErrorConfig),
    time: zenithor.Resource(TimePlugin.Time),
) void {
    const window_flags = ImGuiPlugin.ImGuiWindowFlags.None;

    // Main control window
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 10 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 400, .y = 200 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("Error Tracking Demo", null, window_flags)) {
        ImGuiPlugin.text("Zenithor Error Handling System");
        ImGuiPlugin.separator();

        ImGuiPlugin.textFmt("Total Errors Caught: {}", .{config.value.error_count});
        ImGuiPlugin.textFmt("Current Time: {d:.2}s", .{time.value.total_time});

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Error Generation Controls:");

        // Button to trigger system error
        if (ImGuiPlugin.button("Trigger System Error")) {
            config.value.trigger_system_error = true;
        }

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Error Types:");
        ImGuiPlugin.bulletText("GameLoopError: System failures");
        ImGuiPlugin.bulletText("EventLoopError: Event handler failures");
    }
    ImGuiPlugin.end();

    // Error log window
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 220 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 400, .y = 300 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("Error Log", null, window_flags)) {
        ImGuiPlugin.text("Recent Errors:");
        ImGuiPlugin.separator();

        if (log.value.count == 0) {
            ImGuiPlugin.textColored(
                ImGuiPlugin.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 },
                "No errors yet. Click 'Trigger System Error' to test.",
            );
        } else {
            // Display errors in reverse chronological order
            var i: usize = log.value.count;
            while (i > 0) {
                i -= 1;
                const entry = log.value.slice()[i];

                const color = switch (entry.error_type) {
                    .game_loop => ImGuiPlugin.ImVec4{ .x = 1.0, .y = 0.4, .z = 0.4, .w = 1.0 }, // Red
                    .event_loop => ImGuiPlugin.ImVec4{ .x = 1.0, .y = 0.7, .z = 0.2, .w = 1.0 }, // Orange
                };

                ImGuiPlugin.textColoredFmt(color, "[{d:.2}s] {s}: {s}", .{
                    entry.timestamp,
                    @tagName(entry.error_type),
                    entry.error_name,
                });
            }
        }

        ImGuiPlugin.separator();
        if (ImGuiPlugin.button("Clear Log")) {
            log.value.clear();
            config.value.error_count = 0;
        }
    }
    ImGuiPlugin.end();

    // Information window
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 420, .y = 10 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 370, .y = 510 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("How It Works", null, window_flags)) {
        ImGuiPlugin.text("Error Tracking Architecture");
        ImGuiPlugin.separator();

        ImGuiPlugin.textWrapped("Zenithor's error handling system allows systems to fail gracefully without crashing the application.");
        ImGuiPlugin.spacing();

        ImGuiPlugin.text("When Systems Fail:");
        ImGuiPlugin.bulletText("System returns error (!void)");
        ImGuiPlugin.bulletText("SystemScheduler catches error");
        ImGuiPlugin.bulletText("Error queued as GameLoopError event");
        ImGuiPlugin.bulletText("App continues running");
        ImGuiPlugin.spacing();

        ImGuiPlugin.text("When Event Handlers Fail:");
        ImGuiPlugin.bulletText("Handler returns error (!void)");
        ImGuiPlugin.bulletText("Application catches error");
        ImGuiPlugin.bulletText("Error queued as EventLoopError event");
        ImGuiPlugin.bulletText("App continues running");
        ImGuiPlugin.spacing();

        ImGuiPlugin.text("Error Recovery:");
        ImGuiPlugin.bulletText("Use EventReader to monitor errors");
        ImGuiPlugin.bulletText("Implement recovery logic");
        ImGuiPlugin.bulletText("Log errors for debugging");
        ImGuiPlugin.bulletText("Display user-friendly messages");
        ImGuiPlugin.spacing();

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Code Example:");
        ImGuiPlugin.spacing();
        ImGuiPlugin.textWrapped("fn errorMonitor(");
        ImGuiPlugin.textWrapped("    errors: EventReader(GameLoopError),");
        ImGuiPlugin.textWrapped(") !void {");
        ImGuiPlugin.textWrapped("    var iter = errors.iterator();");
        ImGuiPlugin.textWrapped("    while (iter.next()) |err| {");
        ImGuiPlugin.textWrapped("        // Handle error");
        ImGuiPlugin.textWrapped("    }");
        ImGuiPlugin.textWrapped("}");
    }
    ImGuiPlugin.end();
}
