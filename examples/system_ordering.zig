/// Example: System Staging and Ordering
///
/// Demonstrates system execution order control:
/// - Stages: first -> pre_update -> update -> post_update -> pre_render -> render -> post_render -> last -> post_process
/// - Priority: lower values run first within a stage (default: 0)
/// - Tags: label systems for constraint references
/// - Before/After constraints: explicit ordering via tags
///
/// The example logs system execution to show ordering behavior.
///
/// See: src/core/CLAUDE.md (System Scheduling section)
const std = @import("std");
const zenithor = @import("zenithor");
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;

pub fn main() void {
    zenithor.run(.{SystemOrderingDemo}, .{});
}

// Resource to track execution order
const ExecutionLog = struct {
    entries: [16][]const u8 = undefined,
    count: usize = 0,
    frame: u32 = 0,

    fn log(self: *ExecutionLog, message: []const u8) void {
        if (self.count < self.entries.len) {
            self.entries[self.count] = message;
            self.count += 1;
        }
    }

    fn clear(self: *ExecutionLog) void {
        self.count = 0;
    }

    fn print(self: *const ExecutionLog) void {
        std.debug.print("\n=== Frame {} Execution Order ===\n", .{self.frame});
        for (self.entries[0..self.count], 1..) |entry, i| {
            std.debug.print("{d:2}. {s}\n", .{ i, entry });
        }
        std.debug.print("================================\n\n", .{});
    }
};

const SystemOrderingDemo = struct {
    pub const Components = .{};
    pub const Resources = .{ExecutionLog};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = init, .stage = .first },
        },
        .main = &.{
            // Clear log at start of frame
            .{ .system = clearLog, .stage = .first },

            // === PRIORITY DEMONSTRATION ===
            // Systems with same stage ordered by priority (lower = first)
            .{ .system = systemPriority100, .stage = .update, .config = .{ .priority = 100 } },
            .{ .system = systemPriorityNeg50, .stage = .update, .config = .{ .priority = -50, .tags = &.{"early"} } },
            .{ .system = systemPriority0A, .stage = .update },
            .{ .system = systemPriority0B, .stage = .update },

            // === CONSTRAINT DEMONSTRATION ===
            // Tags + before/after constraints override priority
            .{
                .system = physicsSystem,
                .stage = .update,
                .config = .{
                    .priority = 10,
                    .tags = &.{"physics"},
                    .after = &.{"early"}, // Must run after "early" tag
                },
            },
            .{
                .system = renderingSystem,
                .stage = .update,
                .config = .{
                    .priority = 20,
                    .tags = &.{"rendering"},
                    .after = &.{"physics"}, // Must run after "physics" tag
                },
            },
            .{
                .system = uiSystem,
                .stage = .update,
                .config = .{
                    .tags = &.{"ui"},
                    .after = &.{"rendering"}, // Runs after rendering despite priority 0
                },
            },

            // Print log at end of frame
            .{ .system = printLog, .stage = .last },
        },
    };
};

fn init(commands: anytype) void {
    commands.setResource(ExecutionLog, .{});
}

fn clearLog(log: ResourceMut(ExecutionLog)) void {
    log.clear();
    log.frame += 1;
}

// Priority demonstration systems
fn systemPriorityNeg50(log: ResourceMut(ExecutionLog)) void {
    log.log("1. priority=-50, tags=['early']");
}

fn systemPriority0A(log: ResourceMut(ExecutionLog)) void {
    log.log("2. priority=0 (default) A");
}

fn systemPriority0B(log: ResourceMut(ExecutionLog)) void {
    log.log("3. priority=0 (default) B");
}

fn physicsSystem(log: ResourceMut(ExecutionLog)) void {
    log.log("4. priority=10, tags=['physics'], after=['early']");
}

fn renderingSystem(log: ResourceMut(ExecutionLog)) void {
    log.log("5. priority=20, tags=['rendering'], after=['physics']");
}

fn uiSystem(log: ResourceMut(ExecutionLog)) void {
    log.log("6. priority=0, tags=['ui'], after=['rendering'] <-- constraint overrides priority");
}

fn systemPriority100(log: ResourceMut(ExecutionLog)) void {
    log.log("7. priority=100 (highest)");
}

fn printLog(log: Resource(ExecutionLog)) void {
    log.print();

    std.debug.print("EXPECTED ORDER EXPLANATION:\n", .{});
    std.debug.print("1. priority=-50 runs first (lowest priority value)\n", .{});
    std.debug.print("2-3. priority=0 (A then B, registration order preserved)\n", .{});
    std.debug.print("4. physics: priority=10 + after=['early'] constraint\n", .{});
    std.debug.print("5. rendering: priority=20 + after=['physics'] constraint\n", .{});
    std.debug.print("6. ui: priority=0 but after=['rendering'] - constraint overrides!\n", .{});
    std.debug.print("7. priority=100 runs last (highest priority value)\n\n", .{});

    std.debug.print("KEY CONCEPTS:\n", .{});
    std.debug.print("- Stages define coarse ordering (first/update/render/last)\n", .{});
    std.debug.print("- Priority: lower values run first within a stage\n", .{});
    std.debug.print("- Tags: label systems for constraint references\n", .{});
    std.debug.print("- After/Before: constraints that can override priority\n", .{});
    std.debug.print("- Registration order preserved for equal priorities\n\n", .{});
}
