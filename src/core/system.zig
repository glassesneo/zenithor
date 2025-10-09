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

pub const RegisterFunc = fn (comptime anytype, Stage) void;
