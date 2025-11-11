const std = @import("std");
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const examples = [_]Example{
    .{ .name = "demo_window" },
    .{ .name = "demo_2d" },
    .{ .name = "demo_imgui" },
    .{ .name = "demo_input" },
    .{ .name = "demo_time" },
    .{ .name = "demo_zindex" },
    .{ .name = "demo_circle" },
    .{ .name = "demo_resources" },
    .{ .name = "demo_events" },
    .{ .name = "demo_serialization" },
};

const Example = struct {
    name: []const u8,
};

// Public API for external users building cross-platform apps
pub const PluginModule = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub const AppOptions = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool = false,
    gles3: bool = false,
    wgpu: bool = false,
    imgui_docking: bool = false,
    filesystem: bool = false,
    stack_size_mb: u32 = 5,
    plugins: []const PluginModule = &.{},
};

const ExampleOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool,
    gles3: bool,
    wgpu: bool,
    imgui_docking: bool,
    filesystem: bool,
    stack_size_mb: u32,
    dep_cimgui: *std.Build.Dependency,
    mod_zenithor: *std.Build.Module,
};

const DependencySet = struct {
    sokol: *std.Build.Dependency,
    cimgui: *std.Build.Dependency,
    sparze: *std.Build.Dependency,
    emsdk: ?*std.Build.Dependency = null,
    graphics_plugin_mod: *std.Build.Module,
    time_plugin_mod: *std.Build.Module,
    imgui_plugin_mod: *std.Build.Module,
    input_plugin_mod: *std.Build.Module,
    serialization_plugin_mod: *std.Build.Module,
};

const ExampleResult = struct {
    build: *std.Build.Step,
    run: *std.Build.Step.Run,
};

fn buildExamples(b: *std.Build, options: ExampleOptions) !void {
    const is_wasm = options.target.result.cpu.arch.isWasm();

    // Create "examples" step that builds all examples
    const examples_step = b.step("examples", "Build all examples");

    if (is_wasm) {
        // Create serve-examples step
        const serve_step = b.step("serve-examples", "Build all examples and serve them");
        const serve_deno = b.addSystemCommand(&.{
            "deno",
            "run",
            "--allow-net",
            "--allow-read",
            "--watch",
            "server/server.ts",
        });

        // Build all web examples
        for (examples) |example| {
            const deps = try loadExampleDependencies(b, options);
            const build_desc = b.fmt("Build {s} example", .{example.name});
            const run_desc = b.fmt("Run {s} example", .{example.name});
            const out = try buildWebExample(b, example, options, deps);

            b.step(example.name, build_desc).dependOn(out.build);
            b.step(b.fmt("run-{s}", .{example.name}), run_desc).dependOn(&out.run.step);

            // Add this example's build to aggregate steps
            examples_step.dependOn(out.build);
            serve_step.dependOn(out.build);
            serve_deno.step.dependOn(out.build);
        }

        serve_step.dependOn(&serve_deno.step);
    } else {
        for (examples) |example| {
            const deps = try loadExampleDependencies(b, options);
            const build_desc = b.fmt("Build {s} example", .{example.name});
            const run_desc = b.fmt("Run {s} example", .{example.name});
            const out = buildNativeExample(b, example, options, deps);

            b.step(example.name, build_desc).dependOn(out.build);
            b.step(b.fmt("run-{s}", .{example.name}), run_desc).dependOn(&out.run.step);

            // Add this example's build to aggregate step
            examples_step.dependOn(out.build);
        }
    }
}

fn loadExampleDependencies(b: *std.Build, options: ExampleOptions) !DependencySet {
    const dep_sokol = b.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
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

    // Create plugin modules directly instead of loading via b.dependency()
    // This avoids circular dependency issues
    const graphics_plugin = b.addModule("graphics_plugin", .{
        .root_source_file = b.path("plugins/graphics/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    graphics_plugin.addImport("zenithor", options.mod_zenithor);
    graphics_plugin.addImport("sokol", dep_sokol.module("sokol"));
    graphics_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const time_plugin = b.addModule("time_plugin", .{
        .root_source_file = b.path("plugins/time/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    time_plugin.addImport("zenithor", options.mod_zenithor);
    time_plugin.addImport("sokol", dep_sokol.module("sokol"));
    time_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const imgui_build_options = b.addOptions();
    imgui_build_options.addOption(bool, "docking", options.imgui_docking);

    const imgui_plugin = b.addModule("imgui_plugin", .{
        .root_source_file = b.path("plugins/imgui/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    imgui_plugin.addImport("zenithor", options.mod_zenithor);
    imgui_plugin.addImport("sokol", dep_sokol.module("sokol"));
    imgui_plugin.addImport("sparze", dep_sparze.module("sparze"));
    imgui_plugin.addImport("cimgui", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("cimgui_docking", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("build_options", imgui_build_options.createModule());

    const input_plugin = b.addModule("input_plugin", .{
        .root_source_file = b.path("plugins/input/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    input_plugin.addImport("zenithor", options.mod_zenithor);
    input_plugin.addImport("sokol", dep_sokol.module("sokol"));
    input_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const serialization_plugin = b.addModule("serialization_plugin", .{
        .root_source_file = b.path("plugins/serialization/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    serialization_plugin.addImport("zenithor", options.mod_zenithor);
    serialization_plugin.addImport("sparze", dep_sparze.module("sparze"));

    // Return a modified DependencySet structure that holds modules instead of dependencies
    return .{
        .sokol = dep_sokol,
        .cimgui = dep_cimgui,
        .sparze = dep_sparze,
        .graphics_plugin_mod = graphics_plugin,
        .time_plugin_mod = time_plugin,
        .imgui_plugin_mod = imgui_plugin,
        .input_plugin_mod = input_plugin,
        .serialization_plugin_mod = serialization_plugin,
    };
}

fn createExampleModule(b: *std.Build, example: Example, options: ExampleOptions, deps: DependencySet) *std.Build.Module {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);

    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = deps.sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = deps.cimgui.module(cimgui_config.module_name) },
        },
    });
    mod.addImport("zenithor", options.mod_zenithor);
    mod.addImport("graphics_plugin", deps.graphics_plugin_mod);
    mod.addImport("time_plugin", deps.time_plugin_mod);
    mod.addImport("imgui_plugin", deps.imgui_plugin_mod);
    mod.addImport("input_plugin", deps.input_plugin_mod);
    mod.addImport("serialization_plugin", deps.serialization_plugin_mod);

    return mod;
}

/// Create an application module with all built-in and custom plugins
fn createAppModule(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    zenithor_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imgui_docking: bool,
    deps: DependencySet,
    plugins: []const PluginModule,
) *std.Build.Module {
    const cimgui_config = cimgui.getConfig(imgui_docking);

    const mod = b.createModule(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = deps.sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = deps.cimgui.module(cimgui_config.module_name) },
        },
    });
    mod.addImport("zenithor", zenithor_mod);
    mod.addImport("sparze", deps.sparze.module("sparze"));

    // Add built-in plugins
    mod.addImport("graphics_plugin", deps.graphics_plugin_mod);
    mod.addImport("time_plugin", deps.time_plugin_mod);
    mod.addImport("imgui_plugin", deps.imgui_plugin_mod);
    mod.addImport("input_plugin", deps.input_plugin_mod);
    mod.addImport("serialization_plugin", deps.serialization_plugin_mod);

    // Add custom plugins
    for (plugins) |plugin| {
        mod.addImport(plugin.name, plugin.module);
    }

    return mod;
}

/// Load dependencies for an app build from the zenithor dependency
fn loadAppDependencies(
    zenithor_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool,
    gles3: bool,
    wgpu: bool,
    imgui_docking: bool,
) !DependencySet {
    const b = zenithor_dep.builder;

    const dep_sokol = zenithor_dep.builder.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
        .gl = gl,
        .gles3 = gles3,
        .wgpu = wgpu,
    });

    const cimgui_config = cimgui.getConfig(imgui_docking);

    const dep_cimgui = zenithor_dep.builder.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = zenithor_dep.builder.dependency("sparze", .{
        .target = target,
        .optimize = optimize,
    });

    const zenithor_mod = zenithor_dep.module("zenithor");

    // Create plugin modules
    const graphics_plugin = b.addModule("graphics_plugin", .{
        .root_source_file = zenithor_dep.path("plugins/graphics/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    graphics_plugin.addImport("zenithor", zenithor_mod);
    graphics_plugin.addImport("sokol", dep_sokol.module("sokol"));
    graphics_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const time_plugin = b.addModule("time_plugin", .{
        .root_source_file = zenithor_dep.path("plugins/time/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    time_plugin.addImport("zenithor", zenithor_mod);
    time_plugin.addImport("sokol", dep_sokol.module("sokol"));
    time_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const imgui_build_options = b.addOptions();
    imgui_build_options.addOption(bool, "docking", imgui_docking);

    const imgui_plugin = b.addModule("imgui_plugin", .{
        .root_source_file = zenithor_dep.path("plugins/imgui/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    imgui_plugin.addImport("zenithor", zenithor_mod);
    imgui_plugin.addImport("sokol", dep_sokol.module("sokol"));
    imgui_plugin.addImport("sparze", dep_sparze.module("sparze"));
    imgui_plugin.addImport("cimgui", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("cimgui_docking", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("build_options", imgui_build_options.createModule());

    const input_plugin = b.addModule("input_plugin", .{
        .root_source_file = zenithor_dep.path("plugins/input/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_plugin.addImport("zenithor", zenithor_mod);
    input_plugin.addImport("sokol", dep_sokol.module("sokol"));
    input_plugin.addImport("sparze", dep_sparze.module("sparze"));

    const serialization_plugin = b.addModule("serialization_plugin", .{
        .root_source_file = zenithor_dep.path("plugins/serialization/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    serialization_plugin.addImport("zenithor", zenithor_mod);
    serialization_plugin.addImport("sparze", dep_sparze.module("sparze"));

    return .{
        .sokol = dep_sokol,
        .cimgui = dep_cimgui,
        .sparze = dep_sparze,
        .graphics_plugin_mod = graphics_plugin,
        .time_plugin_mod = time_plugin,
        .imgui_plugin_mod = imgui_plugin,
        .input_plugin_mod = input_plugin,
        .serialization_plugin_mod = serialization_plugin,
    };
}

/// Build Emscripten linker arguments
fn buildEmscriptenArgs(b: *std.Build, stack_size_mb: u32) []const []const u8 {
    const stack_arg = b.fmt("-sSTACK_SIZE={d}MB", .{stack_size_mb});

    return &[_][]const u8{
        "-sSHARED_MEMORY=0",
        "-sEXIT_RUNTIME=0",
        stack_arg,
        "-sSTACK_OVERFLOW_CHECK=2",
        "-sINITIAL_MEMORY=64MB",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sASSERTIONS=2",
        "-sSAFE_HEAP=1",
        "-sUSE_PTHREADS=0",
        "--bind",
    };
}

/// Build a native executable for desktop/mobile platforms
/// This is the public API for external users building cross-platform apps
pub fn buildNative(
    zenithor_dep: *std.Build.Dependency,
    options: AppOptions,
) *std.Build.Step.Compile {
    const b = zenithor_dep.builder;
    const zenithor_mod = zenithor_dep.module("zenithor");

    // Load dependencies
    const dep_sokol = zenithor_dep.builder.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
    });

    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const dep_cimgui = zenithor_dep.builder.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = zenithor_dep.builder.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Create app module
    const mod = b.createModule(.{
        .root_source_file = options.root_source_file,
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = dep_cimgui.module(cimgui_config.module_name) },
        },
    });
    mod.addImport("zenithor", zenithor_mod);
    mod.addImport("sparze", dep_sparze.module("sparze"));

    // Add user-specified plugins
    for (options.plugins) |plugin| {
        mod.addImport(plugin.name, plugin.module);
    }

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = mod,
    });

    // Add iOS framework paths for linking
    if (options.target.result.os.tag == .ios) {
        const allocator = b.allocator;
        const sdk_name = if (options.target.result.abi == .simulator) "iphonesimulator" else "iphoneos";
        const xcrun_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
        }) catch {
            return exe;
        };
        defer allocator.free(xcrun_result.stdout);
        defer allocator.free(xcrun_result.stderr);

        if (xcrun_result.term == .Exited and xcrun_result.term.Exited == 0) {
            const sdk_path = std.mem.trim(u8, xcrun_result.stdout, &std.ascii.whitespace);
            if (sdk_path.len > 0) {
                const framework_path = b.fmt("{s}/System/Library/Frameworks", .{sdk_path});
                const framework_lazy: std.Build.LazyPath = .{ .cwd_relative = framework_path };
                exe.root_module.addFrameworkPath(framework_lazy);
            }
        }
    }

    return exe;
}

/// Build a WebAssembly application
/// This is the public API for external users building WASM apps
/// Returns the emscripten link step (not the library artifact)
pub fn buildWeb(
    zenithor_dep: *std.Build.Dependency,
    options: AppOptions,
) !*std.Build.Step {
    const b = zenithor_dep.builder;
    const zenithor_mod = zenithor_dep.module("zenithor");

    // Load dependencies
    const dep_sokol = zenithor_dep.builder.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
    });

    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const dep_cimgui = zenithor_dep.builder.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    const dep_emsdk = dep_sokol.builder.dependency("emsdk", .{});
    dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(dep_emsdk.path("upstream/emscripten/cache/sysroot/include"));
    dep_cimgui.artifact(cimgui_config.clib_name).step.dependOn(&dep_sokol.artifact("sokol_clib").step);
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = zenithor_dep.builder.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Create app module
    const mod = b.createModule(.{
        .root_source_file = options.root_source_file,
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = dep_cimgui.module(cimgui_config.module_name) },
        },
    });
    mod.addImport("zenithor", zenithor_mod);
    mod.addImport("sparze", dep_sparze.module("sparze"));

    // Add user-specified plugins
    for (options.plugins) |plugin| {
        mod.addImport(plugin.name, plugin.module);
    }

    const lib = b.addLibrary(.{
        .name = options.name,
        .root_module = mod,
    });

    // Build Emscripten linker arguments
    const base_args = buildEmscriptenArgs(b, options.stack_size_mb);

    const link = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = options.target,
        .optimize = options.optimize,
        .emsdk = dep_emsdk,
        .use_webgpu = options.wgpu,
        .use_webgl2 = !options.wgpu,
        .use_emmalloc = true,
        .use_filesystem = options.filesystem,
        .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
        .extra_args = base_args,
    });

    return &link.step;
}

fn buildNativeExample(b: *std.Build, example: Example, options: ExampleOptions, deps: DependencySet) ExampleResult {
    const mod = createExampleModule(b, example, options, deps);
    const exe = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });
    exe.root_module.addImport("sparze", deps.sparze.module("sparze"));

    // Add iOS framework paths for linking
    if (options.target.result.os.tag == .ios) {
        const allocator = b.allocator;
        const sdk_name = if (options.target.result.abi == .simulator) "iphonesimulator" else "iphoneos";
        const xcrun_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
        }) catch |err| {
            std.debug.print("Warning: Failed to get iOS SDK path: {}\n", .{err});
            const run = b.addRunArtifact(exe);
            return .{ .build = &exe.step, .run = run };
        };
        defer allocator.free(xcrun_result.stdout);
        defer allocator.free(xcrun_result.stderr);

        if (xcrun_result.term == .Exited and xcrun_result.term.Exited == 0) {
            const sdk_path = std.mem.trim(u8, xcrun_result.stdout, &std.ascii.whitespace);
            if (sdk_path.len > 0) {
                const framework_path = b.fmt("{s}/System/Library/Frameworks", .{sdk_path});
                const framework_lazy: std.Build.LazyPath = .{ .cwd_relative = framework_path };
                exe.root_module.addFrameworkPath(framework_lazy);
            }
        }
    }

    const run = b.addRunArtifact(exe);

    return .{ .build = &exe.step, .run = run };
}

fn buildWebExample(b: *std.Build, example: Example, options: ExampleOptions, deps: DependencySet) !ExampleResult {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const dep_emsdk = deps.sokol.builder.dependency("emsdk", .{});
    options.dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(dep_emsdk.path("upstream/emscripten/cache/sysroot/include"));
    options.dep_cimgui.artifact(cimgui_config.clib_name).step.dependOn(&deps.sokol.artifact("sokol_clib").step);

    const mod = createExampleModule(b, example, options, deps);
    const lib = b.addLibrary(.{
        .name = example.name,
        .root_module = mod,
    });
    lib.root_module.addImport("sparze", deps.sparze.module("sparze"));

    // Build Emscripten linker arguments
    const base_args = buildEmscriptenArgs(b, options.stack_size_mb);

    const link = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = options.target,
        .optimize = options.optimize,
        .emsdk = dep_emsdk,
        .use_webgpu = options.wgpu,
        .use_webgl2 = !options.wgpu,
        .use_emmalloc = true,
        .use_filesystem = options.filesystem,
        .shell_file_path = deps.sokol.path("src/sokol/web/shell.html"),
        .extra_args = base_args,
    });

    b.getInstallStep().dependOn(&link.step);

    const deno = b.addSystemCommand(&.{
        "deno",
        "run",
        "--allow-net",
        "--allow-read",
        "--watch",
        "server/server.ts",
    });
    deno.step.dependOn(&link.step);

    return .{ .build = &link.step, .run = deno };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mod_target = target.result;
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.1.0");
    const gl = b.option(bool, "gl", "Whether to use OpenGL backend") orelse false;
    const gles3 = b.option(bool, "gles3", "Whether to use OpenGL ES3 backend") orelse false;
    const wgpu = b.option(bool, "wgpu", "Whether to use WebGPU backend") orelse false;
    const imgui_docking = b.option(bool, "imgui-docking", "Whether to build with imgui docking support") orelse false;
    const filesystem = b.option(bool, "filesystem", "Enable Emscripten filesystem support (WASM only, increases binary size)") orelse false;
    const stack_size_mb = b.option(u32, "stack-size", "WASM stack size in MB (default: 5, min: 1, max: 16)") orelse 5;

    const cimgui_config = cimgui.getConfig(imgui_docking);

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
        .gl = gl,
        .gles3 = gles3,
        .wgpu = wgpu,
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

    const lib_mod = b.addModule("zenithor", .{
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

    // Export plugin modules for external users
    const graphics_plugin = b.addModule("graphics_plugin", .{
        .root_source_file = b.path("plugins/graphics/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    graphics_plugin.addImport("zenithor", lib_mod);
    graphics_plugin.addImport("sokol", dep_sokol.module("sokol"));
    graphics_plugin.addImport("sparze", sparze_mod);

    const time_plugin = b.addModule("time_plugin", .{
        .root_source_file = b.path("plugins/time/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    time_plugin.addImport("zenithor", lib_mod);
    time_plugin.addImport("sokol", dep_sokol.module("sokol"));
    time_plugin.addImport("sparze", sparze_mod);

    const imgui_plugin = b.addModule("imgui_plugin", .{
        .root_source_file = b.path("plugins/imgui/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    imgui_plugin.addImport("zenithor", lib_mod);
    imgui_plugin.addImport("sokol", dep_sokol.module("sokol"));
    imgui_plugin.addImport("sparze", sparze_mod);
    imgui_plugin.addImport("cimgui", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("cimgui_docking", dep_cimgui.module(cimgui_config.module_name));
    imgui_plugin.addImport("build_options", mod_options.createModule());

    const input_plugin = b.addModule("input_plugin", .{
        .root_source_file = b.path("plugins/input/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_plugin.addImport("zenithor", lib_mod);
    input_plugin.addImport("sokol", dep_sokol.module("sokol"));
    input_plugin.addImport("sparze", sparze_mod);

    const serialization_plugin = b.addModule("serialization_plugin", .{
        .root_source_file = b.path("plugins/serialization/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    serialization_plugin.addImport("zenithor", lib_mod);
    serialization_plugin.addImport("sparze", sparze_mod);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const env_map = std.process.getEnvMap(allocator) catch unreachable;

    if (mod_target.os.tag == .macos) for_darwin: {
        const cups_include_dir = env_map.get("CUPS_INCLUDE_DIR") orelse break :for_darwin;
        const cups_include_path: std.Build.LazyPath = .{ .cwd_relative = cups_include_dir };
        dep_sokol.artifact("sokol_clib").addIncludePath(cups_include_path);
    }

    // iOS SDK configuration: add sysroot for C/C++ compilation
    if (mod_target.os.tag == .ios) for_ios: {
        // Get iOS SDK path via xcrun (requires DEVELOPER_DIR pointing to Xcode)
        const sdk_name = if (mod_target.abi == .simulator) "iphonesimulator" else "iphoneos";
        const xcrun_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
        }) catch break :for_ios;
        defer allocator.free(xcrun_result.stdout);
        defer allocator.free(xcrun_result.stderr);

        if (xcrun_result.term == .Exited and xcrun_result.term.Exited == 0) {
            const sdk_path = std.mem.trim(u8, xcrun_result.stdout, &std.ascii.whitespace);
            if (sdk_path.len > 0) {
                // Add both SDK root and usr/include for C standard library headers
                const sdk_lazy_path: std.Build.LazyPath = .{ .cwd_relative = sdk_path };
                const usr_include_path = b.fmt("{s}/usr/include", .{sdk_path});
                const usr_include_lazy: std.Build.LazyPath = .{ .cwd_relative = usr_include_path };
                const framework_path = b.fmt("{s}/System/Library/Frameworks", .{sdk_path});
                const framework_lazy: std.Build.LazyPath = .{ .cwd_relative = framework_path };

                // Configure both sokol and cimgui with iOS SDK paths
                dep_sokol.artifact("sokol_clib").addSystemIncludePath(sdk_lazy_path);
                dep_sokol.artifact("sokol_clib").addSystemIncludePath(usr_include_lazy);
                dep_sokol.artifact("sokol_clib").addFrameworkPath(framework_lazy);
                dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(sdk_lazy_path);
                dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(usr_include_lazy);
            }
        }
    }

    try buildExamples(b, .{
        .target = target,
        .optimize = optimize,
        .gl = gl,
        .gles3 = gles3,
        .wgpu = wgpu,
        .imgui_docking = imgui_docking,
        .filesystem = filesystem,
        .stack_size_mb = stack_size_mb,
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