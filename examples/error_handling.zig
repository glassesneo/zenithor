/// Example: Event Flow and Error Handling
///
/// Demonstrates graceful error handling in Zenithor:
/// - Systems can return errors with !void signature
/// - Errors are caught and converted to events (not crashes)
/// - GameLoopError: captures system failures during frame execution
/// - EventLoopError: captures event handler failures
/// - Use EventReader to monitor and handle errors
///
/// Click the button to trigger a system error and see it captured.
///
/// See: src/core/CLAUDE.md (Error Handling section)
const std = @import("std");
const zenithor = @import("zenithor");
const BuiltinPlugin = zenithor.BuiltinPlugin;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const EventReader = zenithor.EventReader;
const Shapes2DPlugin = @import("shapes2d_plugin");
const Renderer = @import("renderer_plugin");
const TimePlugin = @import("time_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{ Shapes2DPlugin, TimePlugin, ImGuiPlugin, ErrorDemo }, .{});
}

// Configuration resource
const ErrorConfig = struct {
    trigger_error: bool = false,
    error_count: u32 = 0,
};

// Log of caught errors
const ErrorLog = struct {
    const MAX_ENTRIES = 20;
    const Entry = struct {
        error_name: []const u8,
        timestamp: f64,
    };

    entries: [MAX_ENTRIES]Entry = undefined,
    count: usize = 0,

    fn add(self: *ErrorLog, err: anyerror, timestamp: f64) void {
        if (self.count >= MAX_ENTRIES) {
            // Shift entries to make room
            for (1..self.count) |i| {
                self.entries[i - 1] = self.entries[i];
            }
            self.count -= 1;
        }
        self.entries[self.count] = .{
            .error_name = @errorName(err),
            .timestamp = timestamp,
        };
        self.count += 1;
    }

    fn clear(self: *ErrorLog) void {
        self.count = 0;
    }
};

const ErrorDemo = struct {
    pub const Components = .{};
    pub const Resources = .{ ErrorConfig, ErrorLog };
    // Declare the error events we want to read
    pub const Events = .{
        BuiltinPlugin.GameLoopError,
        BuiltinPlugin.EventLoopError,
    };

    pub const systems = .{
        .startup = &.{
            .{ .system = init, .stage = .first },
        },
        .main = &.{
            // This system can fail intentionally
            .{ .system = errorProneSystem, .stage = .update },
            // This system monitors for errors
            .{ .system = errorMonitor, .stage = .post_update },
            // UI system
            .{ .system = drawUI, .stage = .render },
        },
    };
};

fn init(commands: anytype, pass_action: ResourceMut(Renderer.PassAction)) void {
    pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 };
    commands.setResource(ErrorConfig, .{});
    commands.setResource(ErrorLog, .{});
}

// System that can fail - note the !void return type
fn errorProneSystem(config: ResourceMut(ErrorConfig)) !void {
    if (config.trigger_error) {
        // Reset flag before returning error
        config.trigger_error = false;
        // Return an error - this will be caught and converted to GameLoopError event
        return error.IntentionalDemoError;
    }
    // Normal execution - no error
}

// Monitor system that reads error events
fn errorMonitor(
    game_errors: EventReader(BuiltinPlugin.GameLoopError),
    event_errors: EventReader(BuiltinPlugin.EventLoopError),
    log: ResourceMut(ErrorLog),
    config: ResourceMut(ErrorConfig),
    time: Resource(TimePlugin.Time),
) void {
    const timestamp = time.total_time;

    // Check for game loop errors (from systems)
    for (game_errors.read()) |err_event| {
        log.add(err_event.err, timestamp);
        config.error_count += 1;
    }

    // Check for event loop errors (from event handlers)
    for (event_errors.read()) |err_event| {
        log.add(err_event.err, timestamp);
        config.error_count += 1;
    }
}

fn drawUI(
    config: ResourceMut(ErrorConfig),
    log: ResourceMut(ErrorLog),
    time: Resource(TimePlugin.Time),
) void {
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 400, .y = 300 }, .Once);

    if (ImGuiPlugin.begin("Error Handling Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Error Handling System");
        ImGuiPlugin.separator();

        ImGuiPlugin.textFmt("Errors Caught: {}", .{config.error_count});
        ImGuiPlugin.textFmt("Time: {d:.2}s", .{time.total_time});

        ImGuiPlugin.spacing();
        if (ImGuiPlugin.button("Trigger System Error")) {
            config.trigger_error = true;
        }
        ImGuiPlugin.sameLine();
        if (ImGuiPlugin.button("Clear Log")) {
            log.clear();
            config.error_count = 0;
        }

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Error Log");
        ImGuiPlugin.separator();

        if (log.count == 0) {
            ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "(No errors - click button to trigger one)");
        } else {
            // Show errors in reverse chronological order
            var i: usize = log.count;
            while (i > 0) {
                i -= 1;
                const entry = log.entries[i];
                ImGuiPlugin.textColoredFmt(.{ .x = 1.0, .y = 0.4, .z = 0.4, .w = 1.0 }, "[{d:.2}s] {s}", .{
                    entry.timestamp,
                    entry.error_name,
                });
            }
        }
    }
    ImGuiPlugin.end();

    // Info panel
    ImGuiPlugin.setNextWindowPos(.{ .x = 420, .y = 10 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 350, .y = 300 }, .Once);

    if (ImGuiPlugin.begin("How It Works", null, .None)) {
        ImGuiPlugin.textWrapped("Zenithor catches system errors gracefully:");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "System Error Flow:");
        ImGuiPlugin.bulletText("System returns error (!void)");
        ImGuiPlugin.bulletText("SystemScheduler catches error");
        ImGuiPlugin.bulletText("Error queued as GameLoopError");
        ImGuiPlugin.bulletText("App continues running");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Recovery Pattern:");
        ImGuiPlugin.textWrapped("fn errorMonitor(\n  errors: EventReader(GameLoopError)\n) void {\n  for (errors.read()) |e| {\n    // Handle error\n  }\n}");
    }
    ImGuiPlugin.end();
}
