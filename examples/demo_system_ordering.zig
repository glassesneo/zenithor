const std = @import("std");
const zenithor = @import("zenithor");
const sparze = @import("sparze");

const Resource = sparze.Resource;
const ResourceMut = sparze.ResourceMut;
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;

// Resource to track system execution order
pub const ExecutionLog = struct {
    entries: [10][]const u8 = undefined,
    count: usize = 0,

    pub fn log(self: *ExecutionLog, message: []const u8) void {
        if (self.count >= self.entries.len) {
            std.debug.print("WARNING: ExecutionLog buffer full, ignoring log entry\n", .{});
            return;
        }
        self.entries[self.count] = message;
        self.count += 1;
    }

    pub fn clear(self: *ExecutionLog) void {
        self.count = 0;
    }

    pub fn print(self: *const ExecutionLog) void {
        std.debug.print("\n=== System Execution Order ===\n", .{});
        for (self.entries[0..self.count], 0..) |entry, i| {
            std.debug.print("{d}. {s}\n", .{ i + 1, entry });
        }
        std.debug.print("==============================\n\n", .{});
    }
};

// Define as a plugin module
const SystemOrderingPlugin = @This();

pub const Components = .{};
pub const Resources = .{ExecutionLog};
pub const Events = .{};

fn init(commands: anytype) void {
    commands.setResource(ExecutionLog, .{});
}

pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = clearLogSystem, .stage = .first },
        .{ .system = defaultSystem1, .stage = .update },
        .{ .system = defaultSystem2, .stage = .update },
        .{ .system = highPrioritySystem, .stage = .update, .config = .{ .priority = 100 } },
        .{ .system = lowPrioritySystem, .stage = .update, .config = .{ .priority = -50, .tags = &.{"early"} } },
        .{ .system = physicsSystem, .stage = .update, .config = .{ .priority = 10, .tags = &.{"physics"}, .after = &.{"early"} } },
        .{ .system = renderingSystem, .stage = .update, .config = .{ .priority = 20, .tags = &.{"rendering"}, .after = &.{"physics"} } },
        .{ .system = uiSystem, .stage = .update, .config = .{ .tags = &.{"ui"}, .after = &.{"rendering"}, .before = &.{} } },
        .{ .system = printLogSystem, .stage = .post_update, .config = .{ .priority = 1000 } },
    },
};

fn defaultSystem1(log: ResourceMut(ExecutionLog)) void {
    log.value.log("Default System 1 (priority: 0)");
}

fn defaultSystem2(log: ResourceMut(ExecutionLog)) void {
    log.value.log("Default System 2 (priority: 0)");
}

fn lowPrioritySystem(log: ResourceMut(ExecutionLog)) void {
    log.value.log("Low Priority System (priority: -50, tags: early)");
}

fn highPrioritySystem(log: ResourceMut(ExecutionLog)) void {
    log.value.log("High Priority System (priority: 100)");
}

fn physicsSystem(log: ResourceMut(ExecutionLog)) void {
    log.value.log("Physics System (priority: 10, tags: physics, after: early)");
}

fn renderingSystem(log: ResourceMut(ExecutionLog)) void {
    log.value.log("Rendering System (priority: 20, tags: rendering, after: physics)");
}

fn uiSystem(log: ResourceMut(ExecutionLog)) void {
    log.value.log("UI System (tags: ui, after: rendering)");
}

fn clearLogSystem(log: ResourceMut(ExecutionLog)) void {
    log.value.clear();
}

fn printLogSystem(log: Resource(ExecutionLog)) void {
    log.value.print();

    std.debug.print("Expected order:\n", .{});
    std.debug.print("1. Low Priority (-50) with tag 'early'\n", .{});
    std.debug.print("2. Default System 1 (0)\n", .{});
    std.debug.print("3. Default System 2 (0)\n", .{});
    std.debug.print("4. Physics (10, after 'early')\n", .{});
    std.debug.print("5. Rendering (20, after 'physics')\n", .{});
    std.debug.print("6. UI (0, after 'rendering') - constraint overrides priority\n", .{});
    std.debug.print("7. High Priority (100)\n", .{});
    std.debug.print("\nNote: Default systems with same priority run in registration order\n", .{});
    std.debug.print("Note: Constraints override priority when necessary\n", .{});
}

pub fn main() void {
    zenithor.run(.{SystemOrderingPlugin}, .{});
}
