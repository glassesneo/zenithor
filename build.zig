const std = @import("std");
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const examples = [_]Example{
    .{ .name = "window" },
    .{ .name = "2d_shapes" },
    .{ .name = "imgui_demo" },
};

const Example = struct {
    name: []const u8,
};

const ExampleOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool,
    imgui_docking: bool,
    dep_cimgui: *std.Build.Dependency,
    mod_zenithor: *std.Build.Module,
};

const Options = struct {
    name: []const u8,
    mod: *std.Build.Module,
    dep_sokol: *std.Build.Dependency,
    dep_cimgui: *std.Build.Dependency,
    sparze_mod: *std.Build.Module,
};

fn buildExamples(b: *std.Build, options: ExampleOptions) !void {
    const examples_step = b.step("examples", "Build examples");

    for (examples) |example| {
        const build_step = try buildExample(b, example, options);
        examples_step.dependOn(build_step);
    }
}

fn buildExample(b: *std.Build, example: Example, options: ExampleOptions) !*std.Build.Step {
    const dep_sokol = b.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
    });

    const cimgui_config = cimgui.getConfig(options.imgui_docking);

    const dep_cimgui = b.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = b.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    const sparze_mod = dep_sparze.module("sparze");

    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = dep_cimgui.module(cimgui_config.module_name) },
            // .{ .name = "shader", .module = try createShaderModule(b, dep_sokol) },
        },
    });
    mod.addImport("zenithor", options.mod_zenithor);

    const build_step, const run = if (options.target.result.cpu.arch.isWasm()) wasm: {
        const wasm_example_step = try buildWeb(b, .{
            .name = example.name,
            .mod = mod,
            .dep_sokol = dep_sokol,
            .dep_cimgui = dep_cimgui,
            .sparze_mod = sparze_mod,
        });
        // create a build step which invokes the Emscripten linker
        const dep_emsdk = dep_sokol.builder.dependency("emsdk", .{});
        const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        options.dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(emsdk_incl_path);

        const link_step = try sokol.emLinkStep(b, .{
            .lib_main = wasm_example_step,
            .target = mod.resolved_target.?,
            .optimize = mod.optimize.?,
            .emsdk = dep_emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
            .extra_args = &.{
                "-sSHARED_MEMORY=0",
                "-sEXIT_RUNTIME=0",
                "-sSTACK_SIZE=1MB",
                "-sSTACK_OVERFLOW_CHECK=2",
                "-sINITIAL_MEMORY=64MB",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sASSERTIONS=2",
                "-sSAFE_HEAP=1",
                "-sUSE_PTHREADS=0",
                "--bind",
            },
        });
        // attach Emscripten linker output to default install step
        b.getInstallStep().dependOn(&link_step.step);
        // ...and a special run step to start the web build output via 'emrun'
        const run = sokol.emRunStep(b, .{ .name = example.name, .emsdk = dep_emsdk });
        run.step.dependOn(&link_step.step);
        break :wasm .{ &link_step.step, run };
    } else native: {
        const example_step = buildNative(b, .{
            .name = example.name,
            .mod = mod,
            .dep_sokol = dep_sokol,
            .dep_cimgui = dep_cimgui,
            .sparze_mod = sparze_mod,
        });

        const run = b.addRunArtifact(example_step);
        break :native .{ &example_step.step, run };
    };

    b.step(b.fmt("{s}", .{example.name}), b.fmt("Build {s} example", .{example.name})).dependOn(build_step);
    b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run {s} example", .{example.name})).dependOn(&run.step);

    return build_step;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mod_target = target.result;
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.1.0");
    const gl = b.option(bool, "gl", "Whether to use OpenGL backend") orelse false;
    const imgui_docking = b.option(bool, "imgui-docking", "Whether to build with imgui docking support") orelse false;

    const cimgui_config = cimgui.getConfig(imgui_docking);

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
        .gl = gl,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = b.dependency("sparze", .{
        .target = target,
        .optimize = optimize,
    });
    const sparze_mod = dep_sparze.module("sparze");

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = dep_cimgui.module(cimgui_config.module_name) },
        },
    });

    const mod_options = b.addOptions();
    mod_options.addOption(bool, "docking", imgui_docking);
    lib_mod.addOptions("build_options", mod_options);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zenithor",
        .root_module = lib_mod,
    });

    lib.root_module.addImport("sparze", sparze_mod);

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

    try buildExamples(b, .{
        .target = target,
        .optimize = optimize,
        .gl = gl,
        .imgui_docking = imgui_docking,
        .dep_cimgui = dep_cimgui,
        .mod_zenithor = lib_mod,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

// compile shader via sokol-shdc
fn createShaderModule(b: *std.Build, dep_sokol: *std.Build.Dependency) !*std.Build.Module {
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});
    const mod_shd = try sokol.shdc.createModule(b, "shader", dep_sokol.module("sokol"), .{
        .shdc_dep = dep_shdc,
        .input = "src/shader.glsl",
        .output = "shader.zig",
        .slang = .{
            .hlsl5 = true,
        },
    });

    return mod_shd;
}

fn buildNative(b: *std.Build, options: Options) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = options.mod,
    });

    exe.root_module.addImport("sparze", options.sparze_mod);

    return exe;
}

fn buildWeb(b: *std.Build, options: Options) !*std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = options.name,
        .root_module = options.mod,
    });

    lib.root_module.addImport("sparze", options.sparze_mod);

    return lib;
}
