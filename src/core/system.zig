const std = @import("std");
const EnumArray = std.EnumArray;

const max_systems_per_stage = 1024;

pub fn SystemScheduler(comptime World: type) type {
    return struct {
        const Self = @This();

        systemsByStages: EnumArray(Stage, [max_systems_per_stage]World.SystemPointerType),
        systemCounts: EnumArray(Stage, u16),

        pub fn init() Self {
            return .{
                .systemsByStages = .initFill([_]World.SystemPointerType{undefined} ** max_systems_per_stage),
                .systemCounts = .initFill(0),
            };
        }

        pub fn register(self: *Self, system: World.SystemPointerType, stage: Stage) void {
            const count_ptr = self.systemCounts.getPtr(stage);
            self.systemsByStages.getPtr(stage)[count_ptr.*] = system;
            count_ptr.* += 1;
        }

        pub fn run(self: *Self, world: *World) !void {
            for (self.systemsByStages.values, self.systemCounts.values) |systems, count| {
                for (0..count) |i| {
                    try systems[i](world);
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
    post_render,
    last,
    post_process,
};

// SystemRegistry provides a unified interface for registering systems
pub const SystemRegistry = struct {
    _register_system_func: *const fn (comptime anytype, Stage) void,
    _register_startup_system_func: *const fn (comptime anytype, Stage) void,
    _register_terminate_system_func: *const fn (comptime anytype, Stage) void,

    pub inline fn init(
        register_system_func: *const fn (comptime anytype, Stage) void,
        register_startup_system_func: *const fn (comptime anytype, Stage) void,
        register_terminate_system_func: *const fn (comptime anytype, Stage) void,
    ) SystemRegistry {
        return .{
            ._register_system_func = register_system_func,
            ._register_startup_system_func = register_startup_system_func,
            ._register_terminate_system_func = register_terminate_system_func,
        };
    }

    pub inline fn registerSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_system_func(system_fn, stage);
    }

    pub inline fn registerStartupSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_startup_system_func(system_fn, stage);
    }

    pub inline fn registerTerminateSystem(self: SystemRegistry, comptime system_fn: anytype, stage: Stage) void {
        self._register_terminate_system_func(system_fn, stage);
    }
};

const testing = std.testing;

test "SystemScheduler: registers and runs systems" {
    const TestWorld = struct {
        counter: u32 = 0,

        pub const SystemPointerType = *const fn (*@This()) anyerror!void;

        pub fn runSystem(self: *@This(), comptime system_fn: anytype) !void {
            try system_fn(self);
        }
    };

    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const incrementCounter = struct {
        fn run(world: *TestWorld) !void {
            world.counter += 1;
        }
    }.run;

    scheduler.register(incrementCounter, .update);

    var world = TestWorld{};
    try scheduler.run(&world);

    try testing.expectEqual(@as(u32, 1), world.counter);
}

test "SystemScheduler: runs multiple systems in order" {
    const TestWorld = struct {
        values: [3]u32 = .{ 0, 0, 0 },
        index: usize = 0,

        pub const SystemPointerType = *const fn (*@This()) anyerror!void;

        pub fn runSystem(self: *@This(), comptime system_fn: anytype) !void {
            try system_fn(self);
        }
    };

    const Scheduler = SystemScheduler(TestWorld);
    var scheduler = Scheduler.init();

    const system1 = struct {
        fn run(world: *TestWorld) !void {
            world.values[world.index] = 10;
            world.index += 1;
        }
    }.run;

    const system2 = struct {
        fn run(world: *TestWorld) !void {
            world.values[world.index] = 20;
            world.index += 1;
        }
    }.run;

    scheduler.register(system1, .update);
    scheduler.register(system2, .update);

    var world = TestWorld{};
    try scheduler.run(&world);

    try testing.expectEqual(@as(u32, 10), world.values[0]);
    try testing.expectEqual(@as(u32, 20), world.values[1]);
}

test "SystemRegistry: provides unified registration interface" {
    const TestState = struct {
        var system_called = false;
        var startup_called = false;
        var terminate_called = false;

        fn reset() void {
            system_called = false;
            startup_called = false;
            terminate_called = false;
        }
    };

    TestState.reset();

    const registerSystem = struct {
        fn func(comptime _: anytype, _: Stage) void {
            TestState.system_called = true;
        }
    }.func;

    const registerStartup = struct {
        fn func(comptime _: anytype, _: Stage) void {
            TestState.startup_called = true;
        }
    }.func;

    const registerTerminate = struct {
        fn func(comptime _: anytype, _: Stage) void {
            TestState.terminate_called = true;
        }
    }.func;

    const registry = SystemRegistry.init(registerSystem, registerStartup, registerTerminate);

    const dummySystem = struct {
        fn run() !void {}
    }.run;

    registry.registerSystem(dummySystem, .update);
    registry.registerStartupSystem(dummySystem, .first);
    registry.registerTerminateSystem(dummySystem, .last);

    try testing.expect(TestState.system_called);
    try testing.expect(TestState.startup_called);
    try testing.expect(TestState.terminate_called);
}
