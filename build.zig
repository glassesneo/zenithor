const std = @import("std");

const examples = [_]Example{
    .{ .name = "basic" },
};

const Example = struct {
    name: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mod_target = target.result;
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
        },
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zenithor",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const env_map = std.process.getEnvMap(allocator) catch unreachable;

    if (env_map.get("CUPS_INCLUDE_DIR")) |dir| for_darwin: {
        if (mod_target.os.tag != .macos) break :for_darwin;

        const cups_include_path: std.Build.LazyPath = .{ .cwd_relative = dir };
        dep_sokol.artifact("sokol_clib").addIncludePath(cups_include_path);
    }

    buildExamples(b, .{
        .target = target,
        .optimize = optimize,
        .mod_zenithor = lib_mod,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

const ExampleOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mod_zenithor: *std.Build.Module,
};

fn buildExamples(b: *std.Build, options: ExampleOptions) void {
    const examples_step = b.step("examples", "Build examples");
    const run_examples_step = b.step("run-examples", "Run all examples");

    for (examples) |example| {
        buildExample(b, example, options, examples_step, run_examples_step);
    }
}

fn buildExample(b: *std.Build, example: Example, options: ExampleOptions, examples_step: *std.Build.Step, run_examples_step: *std.Build.Step) void {
    const dep_sokol = b.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
        },
    });
    mod.addImport("zenithor", options.mod_zenithor);

    const example_step = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });

    examples_step.dependOn(&b.addInstallArtifact(example_step, .{}).step);

    const run = b.addRunArtifact(example_step);
    run_examples_step.dependOn(&run.step);
    b.step(b.fmt("{s}", .{example.name}), b.fmt("Build {s} example", .{example.name})).dependOn(&example_step.step);
    b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run {s} example", .{example.name})).dependOn(&run.step);
}
