const std = @import("std");
const builtin = @import("builtin");
const EnumArray = std.EnumArray;
const BuiltinPlugin = @import("builtin.zig");
const sparze = @import("sparze");

const is_debug = builtin.mode == .Debug;

const max_systems_per_stage = 1024;

// SystemConfig provides optional configuration for system registration
pub const SystemConfig = struct {
    priority: i16 = 0,
    tags: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

// SystemMetadata stores information about a registered system
pub const SystemMetadata = struct {
    system_fn: *const fn (*anyopaque) anyerror!void,
    priority: i16 = 0,
    plugin_name: []const u8 = "Unknown",
    plugin_index: u16 = 0,
    tags: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

pub fn SystemScheduler(comptime World: type) type {
    const SystemPointerType = *const fn (*World) anyerror!void;
    return struct {
        const Self = @This();

        systemsByStages: EnumArray(Stage, [max_systems_per_stage]SystemMetadata),
        systemCounts: EnumArray(Stage, u16),

        pub fn init() Self {
            return .{
                .systemsByStages = .initFill([_]SystemMetadata{.{ .system_fn = undefined }} ** max_systems_per_stage),
                .systemCounts = .initFill(0),
            };
        }

        pub fn register(self: *Self, system: SystemPointerType, stage: Stage, plugin_name: []const u8, plugin_index: u16) void {
            const count_ptr = self.systemCounts.getPtr(stage);
            if (builtin.mode == .Debug and count_ptr.* >= max_systems_per_stage) {
                std.debug.panic(
                    "SystemScheduler overflow: stage '{s}' has reached max capacity of {} systems. " ++
                        "Consider increasing max_systems_per_stage or reducing plugin count.",
                    .{ @tagName(stage), max_systems_per_stage },
                );
            }
            // Create metadata with default values
            const metadata = SystemMetadata{
                .system_fn = @ptrCast(system),
                .plugin_name = plugin_name,
                .plugin_index = plugin_index,
            };
            self.systemsByStages.getPtr(stage)[count_ptr.*] = metadata;
            count_ptr.* += 1;
        }

        pub fn registerWithConfig(self: *Self, system: SystemPointerType, stage: Stage, config: SystemConfig, plugin_name: []const u8, plugin_index: u16) void {
            const count_ptr = self.systemCounts.getPtr(stage);
            if (builtin.mode == .Debug and count_ptr.* >= max_systems_per_stage) {
                std.debug.panic(
                    "SystemScheduler overflow: stage '{s}' has reached max capacity of {} systems. " ++
                        "Consider increasing max_systems_per_stage or reducing plugin count.",
                    .{ @tagName(stage), max_systems_per_stage },
                );
            }
            // Create metadata from config
            const metadata = SystemMetadata{
                .system_fn = @ptrCast(system),
                .priority = config.priority,
                .plugin_name = plugin_name,
                .plugin_index = plugin_index,
                .tags = config.tags,
                .before = config.before,
                .after = config.after,
            };
            self.systemsByStages.getPtr(stage)[count_ptr.*] = metadata;
            count_ptr.* += 1;
        }

        // Finalize system registration - sorts by priority and applies constraints
        pub fn finalize(self: *Self) void {
            // Sort each stage's systems
            for (&self.systemsByStages.values, self.systemCounts.values, 0..) |*systems, count, stage_idx| {
                if (count == 0) continue;

                const stage_name = @tagName(@as(Stage, @enumFromInt(stage_idx)));

                // First, validate constraints
                validateConstraints(systems[0..count], stage_name);

                // Then sort: first by priority, then apply constraints
                sortSystems(systems[0..count]);

                // Check for priority overrides (debug only)
                if (builtin.mode == .Debug) {
                    checkPriorityOverrides(systems[0..count], stage_name);
                }
            }

            // Print execution order in debug builds
            if (builtin.mode == .Debug) {
                printSystemExecutionOrder(self);
            }
        }

        fn checkPriorityOverrides(systems: []SystemMetadata, stage_name: []const u8) void {
            // Warn when priority causes systems from dependent plugins to run before their dependencies
            for (systems, 0..) |sys_early, i| {
                for (systems[i + 1 ..]) |sys_late| {
                    if (sys_early.plugin_index > sys_late.plugin_index) {
                        std.debug.print(
                            "\n⚠️  WARNING: Priority override in stage '{s}':\n" ++
                                "   System from '{s}' (plugin #{d}, priority {d}) runs BEFORE\n" ++
                                "   System from '{s}' (plugin #{d}, priority {d})\n" ++
                                "   This may violate plugin dependency order.\n\n",
                            .{
                                stage_name,
                                sys_early.plugin_name,
                                sys_early.plugin_index,
                                sys_early.priority,
                                sys_late.plugin_name,
                                sys_late.plugin_index,
                                sys_late.priority,
                            },
                        );
                    }
                }
            }
        }

        fn printSystemExecutionOrder(self: *Self) void {
            var total_systems: usize = 0;
            for (self.systemCounts.values) |count| {
                total_systems += count;
            }

            if (total_systems == 0) return;

            std.debug.print("\n╔════════════════════════════════════════════════════╗\n", .{});
            std.debug.print("║     System Execution Order (Debug Info)           ║\n", .{});
            std.debug.print("╚════════════════════════════════════════════════════╝\n\n", .{});

            for (self.systemsByStages.values, self.systemCounts.values, 0..) |systems, count, stage_idx| {
                if (count == 0) continue;

                const stage = @as(Stage, @enumFromInt(stage_idx));
                std.debug.print("Stage: {s}\n", .{@tagName(stage)});
                std.debug.print("────────────────────────────────────────────────────\n", .{});

                for (systems[0..count], 0..) |sys, i| {
                    std.debug.print("  {d}. {s:<25} [priority: {d:>4}]", .{
                        i + 1,
                        sys.plugin_name,
                        sys.priority,
                    });

                    if (sys.tags.len > 0) {
                        std.debug.print("\n     Tags: ", .{});
                        for (sys.tags, 0..) |tag, j| {
                            std.debug.print("{s}", .{tag});
                            if (j < sys.tags.len - 1) std.debug.print(", ", .{});
                        }
                    }

                    if (sys.after.len > 0 or sys.before.len > 0) {
                        std.debug.print("\n     Constraints:", .{});
                        if (sys.after.len > 0) {
                            std.debug.print(" after=[", .{});
                            for (sys.after, 0..) |tag, j| {
                                std.debug.print("{s}", .{tag});
                                if (j < sys.after.len - 1) std.debug.print(", ", .{});
                            }
                            std.debug.print("]", .{});
                        }
                        if (sys.before.len > 0) {
                            std.debug.print(" before=[", .{});
                            for (sys.before, 0..) |tag, j| {
                                std.debug.print("{s}", .{tag});
                                if (j < sys.before.len - 1) std.debug.print(", ", .{});
                            }
                            std.debug.print("]", .{});
                        }
                    }

                    std.debug.print("\n", .{});
                }
                std.debug.print("\n", .{});
            }
        }

        fn validateConstraints(systems: []SystemMetadata, stage_name: []const u8) void {
            _ = stage_name;

            // Build tag index
            for (systems, 0..) |system, i| {
                // Check that all .before tags exist
                for (system.before) |before_tag| {
                    var found = false;
                    for (systems) |other| {
                        for (other.tags) |tag| {
                            if (std.mem.eql(u8, tag, before_tag)) {
                                found = true;
                                break;
                            }
                        }
                        if (found) break;
                    }
                    if (!found and (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)) {
                        std.debug.panic(
                            "System at index {} references non-existent tag '{s}' in .before constraint",
                            .{ i, before_tag },
                        );
                    }
                }

                // Check that all .after tags exist
                for (system.after) |after_tag| {
                    var found = false;
                    for (systems) |other| {
                        for (other.tags) |tag| {
                            if (std.mem.eql(u8, tag, after_tag)) {
                                found = true;
                                break;
                            }
                        }
                        if (found) break;
                    }
                    if (!found and (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)) {
                        std.debug.panic(
                            "System at index {} references non-existent tag '{s}' in .after constraint",
                            .{ i, after_tag },
                        );
                    }
                }
            }

            // Check for circular constraints using DFS
            if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                for (systems, 0..) |_, start_idx| {
                    var visited = std.StaticBitSet(max_systems_per_stage).initEmpty();
                    var visiting = std.StaticBitSet(max_systems_per_stage).initEmpty();
                    if (hasCycle(systems, start_idx, &visited, &visiting)) {
                        std.debug.panic(
                            "Circular constraint dependency detected starting from system at index {}",
                            .{start_idx},
                        );
                    }
                }
            }
        }

        fn hasCycle(
            systems: []SystemMetadata,
            idx: usize,
            visited: *std.StaticBitSet(max_systems_per_stage),
            visiting: *std.StaticBitSet(max_systems_per_stage),
        ) bool {
            if (visited.isSet(idx)) return false;
            if (visiting.isSet(idx)) return true;

            visiting.set(idx);

            const system = systems[idx];

            // Check dependencies from .before constraints
            // If system A has .before = "tag_b", then any system with tag_b depends on A
            for (system.before) |before_tag| {
                for (systems, 0..) |other, other_idx| {
                    if (other_idx == idx) continue;
                    for (other.tags) |tag| {
                        if (std.mem.eql(u8, tag, before_tag)) {
                            if (hasCycle(systems, other_idx, visited, visiting)) {
                                return true;
                            }
                        }
                    }
                }
            }

            // Check dependencies from .after constraints
            // If system A has .after = "tag_b", then A depends on any system with tag_b
            for (system.after) |after_tag| {
                for (systems, 0..) |other, other_idx| {
                    if (other_idx == idx) continue;
                    for (other.tags) |tag| {
                        if (std.mem.eql(u8, tag, after_tag)) {
                            if (hasCycle(systems, other_idx, visited, visiting)) {
                                return true;
                            }
                        }
                    }
                }
            }

            visiting.unset(idx);
            visited.set(idx);
            return false;
        }

        fn sortSystems(systems: []SystemMetadata) void {
            // Step 1: Stable sort by priority (lower priority = runs earlier)
            std.sort.insertion(SystemMetadata, systems, {}, comparePriority);

            // Step 2: Apply before/after constraints using topological sort
            // Only reorder systems that have explicit constraints
            applyConstraints(systems);
        }

        fn comparePriority(_: void, a: SystemMetadata, b: SystemMetadata) bool {
            // Lower priority runs first (ascending order)
            return a.priority < b.priority;
        }

        fn applyConstraints(systems: []SystemMetadata) void {
            const n = systems.len;
            if (n <= 1) return;

            // Check if there are any constraints - if not, skip reordering
            var has_constraints = false;
            for (systems) |system| {
                if (system.before.len > 0 or system.after.len > 0) {
                    has_constraints = true;
                    break;
                }
            }
            if (!has_constraints) return;

            // Build dependency graph
            // in_degree[i] = number of systems that must run before system i
            var in_degree: [max_systems_per_stage]u16 = undefined;
            @memset(in_degree[0..n], 0);

            // Build adjacency list: adj[i] contains indices of systems that depend on i
            var adj: [max_systems_per_stage][max_systems_per_stage]u16 = undefined;
            var adj_counts: [max_systems_per_stage]u16 = undefined;
            @memset(adj_counts[0..n], 0);

            // Process constraints
            for (systems, 0..) |system, i| {
                // .after = "tag" means: i must run after any system with "tag"
                for (system.after) |after_tag| {
                    for (systems, 0..) |other, j| {
                        if (i == j) continue;
                        for (other.tags) |tag| {
                            if (std.mem.eql(u8, tag, after_tag)) {
                                // j must run before i
                                adj[j][adj_counts[j]] = @intCast(i);
                                adj_counts[j] += 1;
                                in_degree[i] += 1;
                            }
                        }
                    }
                }

                // .before = "tag" means: i must run before any system with "tag"
                for (system.before) |before_tag| {
                    for (systems, 0..) |other, j| {
                        if (i == j) continue;
                        for (other.tags) |tag| {
                            if (std.mem.eql(u8, tag, before_tag)) {
                                // i must run before j
                                adj[i][adj_counts[i]] = @intCast(j);
                                adj_counts[i] += 1;
                                in_degree[j] += 1;
                            }
                        }
                    }
                }
            }

            // Modified Kahn's algorithm that respects initial ordering
            // Build sorted result by selecting systems in order of their original position
            var sorted: [max_systems_per_stage]SystemMetadata = undefined;
            var sorted_count: usize = 0;
            var processed: [max_systems_per_stage]bool = undefined;
            @memset(processed[0..n], false);

            // Process systems in waves - each wave picks all systems with in_degree == 0
            // Within each wave, maintain original (priority-sorted) order
            while (sorted_count < n) {
                var made_progress = false;

                // Scan in order to find next system(s) with in_degree == 0
                for (0..n) |i| {
                    if (!processed[i] and in_degree[i] == 0) {
                        // Add this system to sorted output
                        sorted[sorted_count] = systems[i];
                        sorted_count += 1;
                        processed[i] = true;
                        made_progress = true;

                        // Reduce in_degree of all systems that depend on this one
                        for (adj[i][0..adj_counts[i]]) |neighbor| {
                            in_degree[neighbor] -= 1;
                        }
                    }
                }

                // If we didn't make progress, there's a cycle (shouldn't happen, validation catches this)
                if (!made_progress) break;
            }

            // Copy sorted result back (only if we successfully sorted everything)
            if (sorted_count == n) {
                @memcpy(systems, sorted[0..n]);
            }
        }

        pub fn run(self: *Self, world: *World) void {
            for (self.systemsByStages.values, self.systemCounts.values) |systems, count| {
                for (0..count) |i| {
                    const system_fn: SystemPointerType = @ptrCast(systems[i].system_fn);
                    system_fn(world) catch |err| {
                        var queue = world.getEventStoragePtrMut(BuiltinPlugin.GameLoopError);
                        queue.enqueue(.{ .err = err }) catch |alloc_err| {
                            std.debug.print("Failed to allocate memory: {any}\n", .{alloc_err});
                        };
                    };
                }
            }
        }
    };
}

pub const Stage = enum {
    first,
    pre_update,
    update,
    post_update,
    pre_render,
    render,
    render_submit,
    post_render,
    last,
    post_process,
};

const CounterResource = struct {
    value: u32 = 0,
};

const SequenceResource = struct {
    values: [3]u32 = .{ 0, 0, 0 },
    index: usize = 0,
};

const TestComponents = struct {};
const TestResources = struct {
    Counter: CounterResource,
    Sequence: SequenceResource,
};
const TestEvents = struct {
    GameLoopError: BuiltinPlugin.GameLoopError,
    EventLoopError: BuiltinPlugin.EventLoopError,
};
const TestWorld = sparze.World(TestComponents, TestResources, TestEvents);

// SystemRegistry provides a unified interface for registering systems
pub const SystemRegistry = struct {
    _register_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
    _register_system_with_config_func: *const fn (comptime anytype, Stage, SystemConfig, []const u8, u16) void,
    _register_startup_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
    _register_terminate_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
    _register_event_handler_func: *const fn (comptime anytype) void,
    plugin_name: []const u8,
    plugin_index: u16,

    pub inline fn init(
        register_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
        register_system_with_config_func: *const fn (comptime anytype, Stage, SystemConfig, []const u8, u16) void,
        register_startup_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
        register_terminate_system_func: *const fn (comptime anytype, Stage, []const u8, u16) void,
        register_event_handler_func: *const fn (comptime anytype) void,
        plugin_name: []const u8,
        plugin_index: u16,
    ) SystemRegistry {
        return .{
            ._register_system_func = register_system_func,
            ._register_system_with_config_func = register_system_with_config_func,
            ._register_startup_system_func = register_startup_system_func,
            ._register_terminate_system_func = register_terminate_system_func,
            ._register_event_handler_func = register_event_handler_func,
            .plugin_name = plugin_name,
            .plugin_index = plugin_index,
        };
    }

    pub inline fn registerSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_system_func(system_fn, stage, self.plugin_name, self.plugin_index);
    }

    pub inline fn registerSystemWithConfig(self: SystemRegistry, comptime system_fn: anytype, stage: Stage, config: SystemConfig) void {
        self._register_system_with_config_func(system_fn, stage, config, self.plugin_name, self.plugin_index);
    }

    pub inline fn registerStartupSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_startup_system_func(system_fn, stage, self.plugin_name, self.plugin_index);
    }

    pub inline fn registerTerminateSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_terminate_system_func(system_fn, stage, self.plugin_name, self.plugin_index);
    }

    pub inline fn registerEventHandler(self: SystemRegistry, comptime handler_fn: anytype) void {
        self._register_event_handler_func(handler_fn);
    }
};

const testing = std.testing;

test "SystemScheduler: registers and runs systems" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const incrementCounter = struct {
        fn run(world: *TestWorld) !void {
            var counter = world.getResourcePtrMut(CounterResource);
            counter.value += 1;
        }
    }.run;

    scheduler.register(incrementCounter, .update, "TestPlugin", 0);

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(CounterResource, .{});
    scheduler.run(&world);

    try testing.expectEqual(@as(u32, 1), world.getResource(CounterResource).value);
}

test "SystemScheduler: runs multiple systems in order" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 10;
            seq.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 20;
            seq.index += 1;
        }
    }.run;

    scheduler.register(system1, .update, "TestPlugin", 0);
    scheduler.register(system2, .update, "TestPlugin", 0);

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(
        SequenceResource,
        SequenceResource{ .values = .{ 0, 0, 0 }, .index = 0 },
    );
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    try testing.expectEqual(@as(u32, 10), sequence.values[0]);
    try testing.expectEqual(@as(u32, 20), sequence.values[1]);
}

test "SystemRegistry: provides unified registration interface" {
    const TestState = struct {
        var system_called = false;
        var startup_called = false;
        var terminate_called = false;
        var event_handler_called = false;

        fn reset() void {
            system_called = false;
            startup_called = false;
            terminate_called = false;
            event_handler_called = false;
        }
    };

    TestState.reset();

    const registerSystem = struct {
        fn func(comptime _: anytype, _: Stage, _: []const u8, _: u16) void {
            TestState.system_called = true;
        }
    }.func;

    const registerSystemWithConfig = struct {
        fn func(comptime _: anytype, _: Stage, _: SystemConfig, _: []const u8, _: u16) void {
            TestState.system_called = true;
        }
    }.func;

    const registerStartup = struct {
        fn func(comptime _: anytype, _: Stage, _: []const u8, _: u16) void {
            TestState.startup_called = true;
        }
    }.func;

    const registerTerminate = struct {
        fn func(comptime _: anytype, _: Stage, _: []const u8, _: u16) void {
            TestState.terminate_called = true;
        }
    }.func;

    const registerEventHandler = struct {
        fn func(comptime _: anytype) void {
            TestState.event_handler_called = true;
        }
    }.func;

    const registry = SystemRegistry.init(registerSystem, registerSystemWithConfig, registerStartup, registerTerminate, registerEventHandler, "TestPlugin", 0);

    const dummySystem = struct {
        fn run() !void {}
    }.run;

    registry.registerSystem(dummySystem, .update);
    registry.registerStartupSystem(dummySystem, .first);
    registry.registerTerminateSystem(dummySystem, .last);
    registry.registerEventHandler(dummySystem);

    try testing.expect(TestState.system_called);
    try testing.expect(TestState.startup_called);
    try testing.expect(TestState.terminate_called);
    try testing.expect(TestState.event_handler_called);
}

test "SystemScheduler: catches and enqueues system errors" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const failingSystem = struct {
        fn run(_: *TestWorld) !void {
            return error.TestError;
        }
    }.run;

    scheduler.register(failingSystem, .update, "TestPlugin", 0);

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    // Run scheduler - should not throw
    scheduler.run(&world);

    // Verify error was enqueued
    const error_storage = world.getEventStoragePtrMut(BuiltinPlugin.GameLoopError);
    try testing.expectEqual(@as(usize, 1), error_storage.write_buffer.items.len);
    try testing.expectEqual(error.TestError, error_storage.write_buffer.items[0].err);
}

test "SystemScheduler: multiple failing systems accumulate errors" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const failingSystem1 = struct {
        fn run(_: *TestWorld) !void {
            return error.FirstError;
        }
    }.run;

    const failingSystem2 = struct {
        fn run(_: *TestWorld) !void {
            return error.SecondError;
        }
    }.run;

    const successSystem = struct {
        fn run(world: *TestWorld) !void {
            var counter = world.getResourcePtrMut(CounterResource);
            counter.value += 1;
        }
    }.run;

    scheduler.register(failingSystem1, .update, "TestPlugin", 0);
    scheduler.register(successSystem, .update, "TestPlugin", 0);
    scheduler.register(failingSystem2, .update, "TestPlugin", 0);

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(CounterResource, .{});

    // Run scheduler - should not throw despite errors
    scheduler.run(&world);

    // Verify successful system ran
    try testing.expectEqual(@as(u32, 1), world.getResource(CounterResource).value);

    // Verify both errors were enqueued
    const error_storage = world.getEventStoragePtrMut(BuiltinPlugin.GameLoopError);
    try testing.expectEqual(@as(usize, 2), error_storage.write_buffer.items.len);
    try testing.expectEqual(error.FirstError, error_storage.write_buffer.items[0].err);
    try testing.expectEqual(error.SecondError, error_storage.write_buffer.items[1].err);
}

test "SystemScheduler: continues execution after system failure" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 10;
            seq.index += 1;
        }
    }.run;

    const failingSystem = struct {
        fn run(_: *TestWorld) !void {
            return error.MiddleError;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 20;
            seq.index += 1;
        }
    }.run;

    scheduler.register(system1, .update, "TestPlugin", 0);
    scheduler.register(failingSystem, .update, "TestPlugin", 0);
    scheduler.register(system2, .update, "TestPlugin", 0);

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(
        SequenceResource,
        SequenceResource{ .values = .{ 0, 0, 0 }, .index = 0 },
    );

    // Run scheduler
    scheduler.run(&world);

    // Verify both systems before and after the failing one executed
    const sequence = world.getResource(SequenceResource);
    try testing.expectEqual(@as(u32, 10), sequence.values[0]);
    try testing.expectEqual(@as(u32, 20), sequence.values[1]);

    // Verify error was captured
    const error_storage = world.getEventStoragePtrMut(BuiltinPlugin.GameLoopError);
    try testing.expectEqual(@as(usize, 1), error_storage.write_buffer.items.len);
    try testing.expectEqual(error.MiddleError, error_storage.write_buffer.items[0].err);
}

test "SystemScheduler: stores priority and tags from SystemConfig" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var counter = world.getResourcePtrMut(CounterResource);
            counter.value += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var counter = world.getResourcePtrMut(CounterResource);
            counter.value += 10;
        }
    }.run;

    // Register with different priorities and tags
    const config1 = SystemConfig{
        .priority = 5,
        .tags = &.{"physics"},
    };
    const config2 = SystemConfig{
        .priority = -3,
        .tags = &.{ "rendering", "graphics" },
        .before = &.{"post_process"},
        .after = &.{"physics"},
    };

    scheduler.registerWithConfig(system1, .update, config1, "TestPlugin", 0);
    scheduler.registerWithConfig(system2, .update, config2, "TestPlugin", 0);

    // Verify metadata was stored correctly
    const update_systems = scheduler.systemsByStages.get(.update);
    try testing.expectEqual(@as(i16, 5), update_systems[0].priority);
    try testing.expectEqual(@as(usize, 1), update_systems[0].tags.len);
    try testing.expectEqualStrings("physics", update_systems[0].tags[0]);
    try testing.expectEqual(@as(usize, 0), update_systems[0].before.len);
    try testing.expectEqual(@as(usize, 0), update_systems[0].after.len);

    try testing.expectEqual(@as(i16, -3), update_systems[1].priority);
    try testing.expectEqual(@as(usize, 2), update_systems[1].tags.len);
    try testing.expectEqualStrings("rendering", update_systems[1].tags[0]);
    try testing.expectEqualStrings("graphics", update_systems[1].tags[1]);
    try testing.expectEqual(@as(usize, 1), update_systems[1].before.len);
    try testing.expectEqualStrings("post_process", update_systems[1].before[0]);
    try testing.expectEqual(@as(usize, 1), update_systems[1].after.len);
    try testing.expectEqualStrings("physics", update_systems[1].after[0]);

    // Verify systems still execute correctly
    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(CounterResource, .{});
    scheduler.run(&world);

    // Both systems should have run
    try testing.expectEqual(@as(u32, 11), world.getResource(CounterResource).value);
}

test "SystemScheduler: sorts systems by priority after finalize" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 10;
            seq.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 20;
            seq.index += 1;
        }
    }.run;

    const system3 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 30;
            seq.index += 1;
        }
    }.run;

    // Register with priorities: high, low, medium
    scheduler.registerWithConfig(system1, .update, .{ .priority = 10 }, "TestPlugin", 0);
    scheduler.registerWithConfig(system2, .update, .{ .priority = -5 }, "TestPlugin", 0);
    scheduler.registerWithConfig(system3, .update, .{ .priority = 0 }, "TestPlugin", 0);

    // Before finalize: registration order (10, -5, 0)
    // After finalize: priority order (-5, 0, 10) -> system2, system3, system1

    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    // Should execute in priority order: system2 (20), system3 (30), system1 (10)
    try testing.expectEqual(@as(u32, 20), sequence.values[0]);
    try testing.expectEqual(@as(u32, 30), sequence.values[1]);
    try testing.expectEqual(@as(u32, 10), sequence.values[2]);
}

test "SystemScheduler: applies before/after constraints" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const physicsSystem = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 10;
            seq.index += 1;
        }
    }.run;

    const renderSystem = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 20;
            seq.index += 1;
        }
    }.run;

    const inputSystem = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 30;
            seq.index += 1;
        }
    }.run;

    // Register in reverse order with constraints
    // Render should run after physics, input should run before physics
    scheduler.registerWithConfig(renderSystem, .update, .{
        .tags = &.{"rendering"},
        .after = &.{"physics"},
    }, "TestPlugin", 0);
    scheduler.registerWithConfig(physicsSystem, .update, .{
        .tags = &.{"physics"},
        .after = &.{"input"},
    }, "TestPlugin", 0);
    scheduler.registerWithConfig(inputSystem, .update, .{
        .tags = &.{"input"},
    }, "TestPlugin", 0);

    // Constraints: input -> physics -> rendering
    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    // Should execute: input (30), physics (10), rendering (20)
    try testing.expectEqual(@as(u32, 30), sequence.values[0]);
    try testing.expectEqual(@as(u32, 10), sequence.values[1]);
    try testing.expectEqual(@as(u32, 20), sequence.values[2]);
}

test "SystemScheduler: priority and constraints work together" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 10;
            seq.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 20;
            seq.index += 1;
        }
    }.run;

    const system3 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 30;
            seq.index += 1;
        }
    }.run;

    // system1: high priority, no constraints
    // system2: low priority, but must run before system3
    // system3: medium priority, must run after system2
    scheduler.registerWithConfig(system1, .update, .{
        .priority = 100,
        .tags = &.{"high"},
    }, "TestPlugin", 0);
    scheduler.registerWithConfig(system2, .update, .{
        .priority = -50,
        .tags = &.{"low"},
    }, "TestPlugin", 0);
    scheduler.registerWithConfig(system3, .update, .{
        .priority = 0,
        .tags = &.{"medium"},
        .after = &.{"low"},
    }, "TestPlugin", 0);

    // Priority alone would give: system2 (-50), system3 (0), system1 (100)
    // Constraints don't change this (system3 already after system2)
    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    try testing.expectEqual(@as(u32, 20), sequence.values[0]);
    try testing.expectEqual(@as(u32, 30), sequence.values[1]);
    try testing.expectEqual(@as(u32, 10), sequence.values[2]);
}

test "SystemScheduler: stable sort preserves registration order for equal priorities" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    // Register 5 systems with the same priority (default 0)
    // They should execute in registration order: 1, 2, 3, 4, 5
    const system1 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 1;
            seq.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 2;
            seq.index += 1;
        }
    }.run;

    const system3 = struct {
        fn run(world: *TestWorld) !void {
            var seq = world.getResourcePtrMut(SequenceResource);
            seq.values[seq.index] = 3;
            seq.index += 1;
        }
    }.run;

    // Register all with default priority (0) - should maintain order
    scheduler.registerWithConfig(system1, .update, .{ .priority = 0 }, "TestPlugin", 0);
    scheduler.registerWithConfig(system2, .update, .{ .priority = 0 }, "TestPlugin", 0);
    scheduler.registerWithConfig(system3, .update, .{ .priority = 0 }, "TestPlugin", 0);

    // Finalize should use stable sort, preserving registration order
    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    try world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    // Should maintain registration order: 1, 2, 3
    try testing.expectEqual(@as(u32, 1), sequence.values[0]);
    try testing.expectEqual(@as(u32, 2), sequence.values[1]);
    try testing.expectEqual(@as(u32, 3), sequence.values[2]);
}
