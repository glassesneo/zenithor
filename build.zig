const std = @import("std");
const Build = std.Build;
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

// Public API for external plugins
pub const PluginModule = struct {
    name: []const u8,
    module: *Build.Module,
};

pub const AppOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool = false,
    gles3: bool = false,
    wgpu: bool = false,
    imgui_docking: bool = false,
    filesystem: bool = false,
    stack_size_mb: u32 = 5,
    default_plugins: []const []const u8 = &.{},
    plugins: []const PluginModule = &.{},
};

const ExampleOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool,
    gles3: bool,
    wgpu: bool,
    imgui_docking: bool,
    filesystem: bool,
    stack_size_mb: u32,
    dep_cimgui: *Build.Dependency,
    mod_zenithor: *Build.Module,
};

const DependencySet = struct {
    sokol: *Build.Dependency,
    cimgui: *Build.Dependency,
    sparze: *Build.Dependency,
    emsdk: ?*Build.Dependency = null,
    graphics_plugin_mod: *Build.Module,
    time_plugin_mod: *Build.Module,
    imgui_plugin_mod: *Build.Module,
    input_plugin_mod: *Build.Module,
    serialization_plugin_mod: *Build.Module,
};

const ExampleResult = struct {
    build: *Build.Step,
    run: *Build.Step.Run,
};

// ========== HELPER FUNCTIONS ==========

/// Wire core imports (sokol, cimgui, zenithor, sparze) to a module
fn wireModuleImports(
    target_module: *Build.Module,
    sokol_mod: *Build.Module,
    cimgui_mod: *Build.Module,
    cimgui_module_name: []const u8,
    zenithor_mod: *Build.Module,
    sparze_mod: *Build.Module,
) void {
    target_module.addImport("sokol", sokol_mod);
    target_module.addImport(cimgui_module_name, cimgui_mod);
    target_module.addImport("zenithor", zenithor_mod);
    target_module.addImport("sparze", sparze_mod);
}

/// Add standard plugin imports (graphics, time, imgui, input, serialization) to module
fn wireStandardPlugins(target_module: *Build.Module, deps: DependencySet) void {
    target_module.addImport("graphics_plugin", deps.graphics_plugin_mod);
    target_module.addImport("time_plugin", deps.time_plugin_mod);
    target_module.addImport("imgui_plugin", deps.imgui_plugin_mod);
    target_module.addImport("input_plugin", deps.input_plugin_mod);
    target_module.addImport("serialization_plugin", deps.serialization_plugin_mod);
}

/// Configure cimgui artifact with Emscripten system includes and sokol dependency
fn setupEmscriptenCimgui(
    dep_cimgui: *Build.Dependency,
    dep_sokol: *Build.Dependency,
    cimgui_clib_name: []const u8,
) void {
    const dep_emsdk = dep_sokol.builder.dependency("emsdk", .{});
    dep_cimgui.artifact(cimgui_clib_name).addSystemIncludePath(
        dep_emsdk.path("upstream/emscripten/cache/sysroot/include"),
    );
    dep_cimgui.artifact(cimgui_clib_name).step.dependOn(
        &dep_sokol.artifact("sokol_clib").step,
    );
}

fn buildExamples(b: *Build, options: ExampleOptions) !void {
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
            "server/examples.ts",
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

fn loadExampleDependencies(b: *Build, options: ExampleOptions) !DependencySet {
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

/// Build Emscripten linker arguments
fn buildEmscriptenArgs(b: *Build, stack_size_mb: u32) []const []const u8 {
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
    b: *Build,
    dep_zenithor: *Build.Dependency,
    exe: *Build.Step.Compile,
    options: AppOptions,
) void {
    _ = b;
    const mod_zenithor = dep_zenithor.module("zenithor");

    // Load dependencies
    const dep_sokol = dep_zenithor.builder.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
    });

    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const dep_cimgui = dep_zenithor.builder.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = dep_zenithor.builder.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Wire core dependencies
    wireModuleImports(
        exe.root_module,
        dep_sokol.module("sokol"),
        dep_cimgui.module(cimgui_config.module_name),
        cimgui_config.module_name,
        mod_zenithor,
        dep_sparze.module("sparze"),
    );

    // Add default plugins
    for (options.default_plugins) |plugin_name| {
        const plugin_module = dep_zenithor.module(plugin_name);
        exe.root_module.addImport(plugin_name, plugin_module);
    }

    // Add user-specified plugins
    for (options.plugins) |plugin| {
        exe.root_module.addImport(plugin.name, plugin.module);
    }
}

/// Build a WebAssembly application
/// This is the public API for external users building WASM apps
/// Returns the emscripten link step (not the library artifact)
pub fn buildWeb(
    b: *Build,
    dep_zenithor: *Build.Dependency,
    lib: *Build.Step.Compile,
    options: AppOptions,
) !*Build.Step {
    const mod_zenithor = dep_zenithor.module("zenithor");

    // Load dependencies
    const dep_sokol = dep_zenithor.builder.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
    });

    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const dep_cimgui = dep_zenithor.builder.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Setup Emscripten-specific cimgui configuration
    setupEmscriptenCimgui(dep_cimgui, dep_sokol, cimgui_config.clib_name);
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = dep_zenithor.builder.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    // Wire core dependencies
    wireModuleImports(
        lib.root_module,
        dep_sokol.module("sokol"),
        dep_cimgui.module(cimgui_config.module_name),
        cimgui_config.module_name,
        mod_zenithor,
        dep_sparze.module("sparze"),
    );

    // Add default plugins
    for (options.default_plugins) |plugin_name| {
        const plugin_module = dep_zenithor.module(plugin_name);
        lib.root_module.addImport(plugin_name, plugin_module);
    }
    // Add user-specified plugins
    for (options.plugins) |plugin| {
        lib.root_module.addImport(plugin.name, plugin.module);
    }

    // Build Emscripten linker arguments
    const base_args = buildEmscriptenArgs(b, options.stack_size_mb);

    const dep_emsdk = dep_sokol.builder.dependency("emsdk", .{});
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

fn buildNativeExample(b: *Build, example: Example, options: ExampleOptions, deps: DependencySet) ExampleResult {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);

    // Create module with root source file (using .imports for sokol and cimgui like the original code)
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = deps.sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = deps.cimgui.module(cimgui_config.module_name) },
        },
    });

    // Wire up remaining core dependencies (zenithor and sparze)
    mod.addImport("zenithor", options.mod_zenithor);
    mod.addImport("sparze", deps.sparze.module("sparze"));

    // Wire up standard plugins
    wireStandardPlugins(mod, deps);

    // Create executable with the configured module
    const exe = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });

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
                const framework_lazy: Build.LazyPath = .{ .cwd_relative = framework_path };
                exe.root_module.addFrameworkPath(framework_lazy);
            }
        }
    }

    const run = b.addRunArtifact(exe);

    return .{ .build = &exe.step, .run = run };
}

fn buildWebExample(b: *Build, example: Example, options: ExampleOptions, deps: DependencySet) !ExampleResult {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);

    // Setup Emscripten-specific cimgui configuration (matching old code exactly)
    const dep_emsdk = deps.sokol.builder.dependency("emsdk", .{});
    options.dep_cimgui.artifact(cimgui_config.clib_name).addSystemIncludePath(dep_emsdk.path("upstream/emscripten/cache/sysroot/include"));
    options.dep_cimgui.artifact(cimgui_config.clib_name).step.dependOn(&deps.sokol.artifact("sokol_clib").step);

    // Create module with root source file (using .imports for sokol and cimgui like the original code)
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = deps.sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = deps.cimgui.module(cimgui_config.module_name) },
        },
    });

    // Wire up zenithor (sparze will be added after library creation, like the original code)
    mod.addImport("zenithor", options.mod_zenithor);

    // Wire up standard plugins
    wireStandardPlugins(mod, deps);

    // Create library with the configured module
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
        "server/shell.ts",
        example.name,
    });
    deno.step.dependOn(&link.step);

    return .{ .build = &link.step, .run = deno };
}

pub fn build(b: *Build) !void {
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
        const cups_include_path: Build.LazyPath = .{ .cwd_relative = cups_include_dir };
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
                const sdk_lazy_path: Build.LazyPath = .{ .cwd_relative = sdk_path };
                const usr_include_path = b.fmt("{s}/usr/include", .{sdk_path});
                const usr_include_lazy: Build.LazyPath = .{ .cwd_relative = usr_include_path };
                const framework_path = b.fmt("{s}/System/Library/Frameworks", .{sdk_path});
                const framework_lazy: Build.LazyPath = .{ .cwd_relative = framework_path };

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
fn createShaderModule(b: *Build, dep_sokol: *Build.Dependency) !*Build.Module {
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
