const std = @import("std");
const builtin = @import("builtin");
const EnumArray = std.EnumArray;
const BuiltinPlugin = @import("builtin.zig");
const sparze = @import("sparze");

const max_systems_per_stage = 1024;
// Maximum dependencies a single system can have (for adjacency list)
// Much smaller than max_systems_per_stage to avoid stack overflow on WASM
const max_deps_per_system = 32;

/// Optional configuration for a system descriptor in `pub const systems`.
///
/// Ubiquitous language: **System Ordering**, **Stage**, **Priority**, **Tags**, **Constraints**.
///
/// Ordering semantics within a stage:
/// 1. Stable sort by `priority` (lower runs earlier)
/// 2. Apply `before`/`after` constraints (by tag) via topological sort
/// 3. In Debug/ReleaseSafe, invalid constraints panic during `finalize()`
pub const SystemConfig = struct {
    priority: i16 = 0,
    tags: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

// SystemDecl is defined inline in plugin declarations as anonymous structs
// Example: .{ .system = myFn, .stage = .update, .config = .{ .priority = 10 } }
// No explicit type needed - the compiler infers the structure

/// Internal scheduling metadata for a registered system.
///
/// Stores plugin diagnostics (name, index) and ordering configuration (priority, tags, constraints).
/// Used by `SystemScheduler.finalize()` for priority sort and topological constraint resolution.
pub const SystemMetadata = struct {
    system_fn: *const fn (*anyopaque) anyerror!void,
    priority: i16 = 0,
    plugin_name: []const u8 = "Unknown",
    plugin_index: u16 = 0,
    tags: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

/// System scheduler with two-phase ordering: priority sort → constraint resolution.
///
/// Ubiquitous language: **System Ordering**, **Priority Sort**, **Topological Sort**, **Constraints**.
///
/// Registration stores systems in declaration order. `finalize()` applies:
/// 1. Stable priority sort (lower values run first)
/// 2. Before/after constraint resolution (topological sort preserving priority groups)
/// 3. Validation (Debug/ReleaseSafe): missing tags, circular dependencies → panic
///
/// WASM constraint: `max_deps_per_system = 32` to avoid stack overflow during topo sort.
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

        // registerDecl registers a system from a declarative system descriptor (anonymous struct)
        // Expected format: .{ .system = fn, .stage = Stage, .config = SystemConfig or partial }
        pub fn registerDecl(self: *Self, comptime decl: anytype, plugin_name: []const u8, plugin_index: u16) void {
            const system_fn = decl.system;
            const stage = decl.stage;

            // Build complete SystemConfig from partial config if provided
            const config: SystemConfig = if (@hasField(@TypeOf(decl), "config")) blk: {
                const partial = decl.config;
                var cfg = SystemConfig{};
                if (@hasField(@TypeOf(partial), "priority")) cfg.priority = partial.priority;
                if (@hasField(@TypeOf(partial), "tags")) cfg.tags = partial.tags;
                if (@hasField(@TypeOf(partial), "before")) cfg.before = partial.before;
                if (@hasField(@TypeOf(partial), "after")) cfg.after = partial.after;
                break :blk cfg;
            } else SystemConfig{};

            const wrapper = struct {
                fn run(world: *World) !void {
                    try world.runSystem(system_fn);
                }
            }.run;
            self.registerWithConfig(wrapper, stage, config, plugin_name, plugin_index);
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
            // Use max_deps_per_system instead of max_systems_per_stage to avoid stack overflow on WASM
            // (1024 * 1024 * 2 = 2MB would overflow the stack)
            var adj: [max_systems_per_stage][max_deps_per_system]u16 = undefined;
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
                                if (adj_counts[j] >= max_deps_per_system) {
                                    // In debug/release-safe: panic to alert developer
                                    // In release-fast/release-small: skip silently (validated at build time)
                                    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                                        @panic("Too many dependencies for system - increase max_deps_per_system");
                                    }
                                    continue;
                                }
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
                                if (adj_counts[i] >= max_deps_per_system) {
                                    // In debug/release-safe: panic to alert developer
                                    // In release-fast/release-small: skip silently (validated at build time)
                                    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                                        @panic("Too many dependencies for system - increase max_deps_per_system");
                                    }
                                    continue;
                                }
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

/// Fixed execution phases within a frame.
///
/// Ubiquitous language: **Frame**, **Update**, **Render**, **Post-process**.
/// See `docs/SYSTEM_ORDERING.md` for stage guidelines and examples.
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

const TestPosition = struct {
    x: f32,
    y: f32,
};

const TestVelocity = struct {
    dx: f32,
    dy: f32,
};

const TestComponents = .{
    TestPosition,
    TestVelocity,
};

const TestMovementGroup = struct {
    TestPosition,
    TestVelocity,
};

const TestResources = .{
    CounterResource,
    SequenceResource,
};
const TestEvents = .{
    BuiltinPlugin.GameLoopError,
    BuiltinPlugin.EventLoopError,
};
const TestGroups = .{
    TestMovementGroup,
};
const TestWorld = sparze.World(TestComponents, TestResources, TestEvents, TestGroups);

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

    world.setResource(CounterResource, .{});
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

    world.setResource(
        SequenceResource,
        SequenceResource{ .values = .{ 0, 0, 0 }, .index = 0 },
    );
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    try testing.expectEqual(@as(u32, 10), sequence.values[0]);
    try testing.expectEqual(@as(u32, 20), sequence.values[1]);
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

    world.setResource(CounterResource, .{});

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

    world.setResource(
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

    world.setResource(CounterResource, .{});
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

    world.setResource(SequenceResource, .{});
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

    world.setResource(SequenceResource, .{});
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

    world.setResource(SequenceResource, .{});
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

    world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    // Should maintain registration order: 1, 2, 3
    try testing.expectEqual(@as(u32, 1), sequence.values[0]);
    try testing.expectEqual(@as(u32, 2), sequence.values[1]);
    try testing.expectEqual(@as(u32, 3), sequence.values[2]);
}

test "SystemScheduler: registerDecl with anonymous struct descriptors" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    // System functions using Sparze parameter injection (not direct world access)
    const system1 = struct {
        fn run(seq: sparze.ResourceMut(SequenceResource)) !void {
            seq.value.values[seq.value.index] = 1;
            seq.value.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(seq: sparze.ResourceMut(SequenceResource)) !void {
            seq.value.values[seq.value.index] = 2;
            seq.value.index += 1;
        }
    }.run;

    const system3 = struct {
        fn run(seq: sparze.ResourceMut(SequenceResource)) !void {
            seq.value.values[seq.value.index] = 3;
            seq.value.index += 1;
        }
    }.run;

    // Register using anonymous struct descriptors (like pub const systems declarations)
    scheduler.registerDecl(.{ .system = system1, .stage = .update }, "TestPlugin", 0);
    scheduler.registerDecl(.{ .system = system2, .stage = .update, .config = .{ .priority = 10 } }, "TestPlugin", 0);
    scheduler.registerDecl(.{ .system = system3, .stage = .update, .config = .{ .tags = &.{"tagged"}, .priority = -10 } }, "TestPlugin", 0);

    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    world.setResource(SequenceResource, .{});
    scheduler.run(&world);

    const sequence = world.getResource(SequenceResource);
    // Should run in priority order: system3 (priority -10), system1 (priority 0), system2 (priority 10)
    try testing.expectEqual(@as(u32, 3), sequence.values[0]);
    try testing.expectEqual(@as(u32, 1), sequence.values[1]);
    try testing.expectEqual(@as(u32, 2), sequence.values[2]);
}

test "SystemScheduler: registerDecl with partial config builds complete SystemConfig" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const taggedSystem = struct {
        fn run(counter: sparze.ResourceMut(CounterResource)) !void {
            counter.value.value += 1;
        }
    }.run;

    const constrainedSystem = struct {
        fn run(counter: sparze.ResourceMut(CounterResource)) !void {
            counter.value.value += 10;
        }
    }.run;

    // Register with only tags (no priority specified)
    scheduler.registerDecl(.{ .system = taggedSystem, .stage = .update, .config = .{ .tags = &.{"first"} } }, "TestPlugin", 0);

    // Register with after constraint (depends on "first" tag)
    scheduler.registerDecl(.{ .system = constrainedSystem, .stage = .update, .config = .{ .after = &.{"first"} } }, "TestPlugin", 0);

    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    world.setResource(CounterResource, .{});
    scheduler.run(&world);

    // Constrained system should run after tagged system: 1 + 10 = 11
    try testing.expectEqual(@as(u32, 11), world.getResource(CounterResource).value);
}

test "SystemScheduler: registerDecl wraps system for runSystem parameter injection" {
    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    // System that uses Sparze parameter injection pattern
    const resourceSystem = struct {
        fn run(counter: sparze.ResourceMut(CounterResource)) !void {
            counter.value.value += 42;
        }
    }.run;

    scheduler.registerDecl(.{ .system = resourceSystem, .stage = .update }, "TestPlugin", 0);
    scheduler.finalize();

    var world = TestWorld.init(testing.allocator);
    defer world.deinit();

    world.setResource(CounterResource, .{});
    scheduler.run(&world);

    // Verify parameter injection worked
    try testing.expectEqual(@as(u32, 42), world.getResource(CounterResource).value);
}
