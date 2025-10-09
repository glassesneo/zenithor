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
