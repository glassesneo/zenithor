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

fn attachExampleSteps(
    b: *Build,
    example: Example,
    result: ExampleResult,
    examples_step: *Build.Step,
    extra_build_steps: []const *Build.Step,
) void {
    const build_desc = b.fmt("Build {s} example", .{example.name});
    const run_desc = b.fmt("Run {s} example", .{example.name});

    b.step(example.name, build_desc).dependOn(result.build);
    b.step(b.fmt("run-{s}", .{example.name}), run_desc).dependOn(&result.run.step);

    examples_step.dependOn(result.build);
    for (extra_build_steps) |step| {
        step.dependOn(result.build);
    }
}

fn buildExamples(b: *Build, options: ExampleOptions) !void {
    const is_wasm = options.target.result.cpu.arch.isWasm();

    // Create "examples" step that builds all examples
    const examples_step = b.step("examples", "Build all examples");
    const deps = try loadExampleDependencies(b, options);

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
            const out = try buildWebExample(b, example, options, deps);
            attachExampleSteps(b, example, out, examples_step, &.{ serve_step, &serve_deno.step });
        }

        serve_step.dependOn(&serve_deno.step);
    } else {
        for (examples) |example| {
            const out = buildNativeExample(b, example, options, deps);
            attachExampleSteps(b, example, out, examples_step, &.{});
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
    const sokol_mod = dep_sokol.module("sokol");

    const cimgui_config = cimgui.getConfig(options.imgui_docking);

    const dep_cimgui = b.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    const cimgui_mod = dep_cimgui.module(cimgui_config.module_name);

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = b.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    const sparze_mod = dep_sparze.module("sparze");

    const standard_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = options.mod_zenithor },
        .{ .name = "sokol", .module = sokol_mod },
        .{ .name = "sparze", .module = sparze_mod },
    };

    // Create plugin modules directly instead of loading via b.dependency()
    // This avoids circular dependency issues
    const graphics_plugin = b.addModule("graphics_plugin", .{
        .root_source_file = b.path("plugins/graphics/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &standard_imports,
    });

    const time_plugin = b.addModule("time_plugin", .{
        .root_source_file = b.path("plugins/time/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &standard_imports,
    });

    const imgui_build_options = b.addOptions();
    imgui_build_options.addOption(bool, "docking", options.imgui_docking);
    const imgui_build_options_mod = imgui_build_options.createModule();

    const imgui_plugin = b.addModule("imgui_plugin", .{
        .root_source_file = b.path("plugins/imgui/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &(standard_imports ++ [_]Build.Module.Import{
            .{ .name = "cimgui", .module = cimgui_mod },
            .{ .name = "cimgui_docking", .module = cimgui_mod },
            .{ .name = "build_options", .module = imgui_build_options_mod },
        }),
    });

    const input_plugin = b.addModule("input_plugin", .{
        .root_source_file = b.path("plugins/input/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &standard_imports,
    });

    const serialization_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = options.mod_zenithor },
        .{ .name = "sparze", .module = sparze_mod },
    };
    const serialization_plugin = b.addModule("serialization_plugin", .{
        .root_source_file = b.path("plugins/serialization/src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = serialization_imports[0..],
    });

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

    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "sokol", .module = deps.sokol.module("sokol") },
            .{ .name = cimgui_config.module_name, .module = deps.cimgui.module(cimgui_config.module_name) },
            .{ .name = "zenithor", .module = options.mod_zenithor },
            .{ .name = "sparze", .module = deps.sparze.module("sparze") },
            .{ .name = "graphics_plugin", .module = deps.graphics_plugin_mod },
            .{ .name = "time_plugin", .module = deps.time_plugin_mod },
            .{ .name = "imgui_plugin", .module = deps.imgui_plugin_mod },
            .{ .name = "input_plugin", .module = deps.input_plugin_mod },
            .{ .name = "serialization_plugin", .module = deps.serialization_plugin_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });

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
            .{ .name = "zenithor", .module = options.mod_zenithor },
            .{ .name = "sparze", .module = deps.sparze.module("sparze") },
            .{ .name = "graphics_plugin", .module = deps.graphics_plugin_mod },
            .{ .name = "time_plugin", .module = deps.time_plugin_mod },
            .{ .name = "imgui_plugin", .module = deps.imgui_plugin_mod },
            .{ .name = "input_plugin", .module = deps.input_plugin_mod },
            .{ .name = "serialization_plugin", .module = deps.serialization_plugin_mod },
        },
    });

    // Create library with the configured module
    const lib = b.addLibrary(.{
        .name = example.name,
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
            .{ .name = "sparze", .module = sparze_mod },
        },
    });

    const mod_options = b.addOptions();
    mod_options.addOption(bool, "docking", imgui_docking);
    const mod_options_module = mod_options.createModule();
    lib_mod.addOptions("build_options", mod_options);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zenithor",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exported_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = lib_mod },
        .{ .name = "sokol", .module = dep_sokol.module("sokol") },
        .{ .name = "sparze", .module = sparze_mod },
    };
    const exported_serialization_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = lib_mod },
        .{ .name = "sparze", .module = sparze_mod },
    };

    // Export plugin modules for external users
    _ = b.addModule("graphics_plugin", .{
        .root_source_file = b.path("plugins/graphics/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });

    _ = b.addModule("time_plugin", .{
        .root_source_file = b.path("plugins/time/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });

    _ = b.addModule("imgui_plugin", .{
        .root_source_file = b.path("plugins/imgui/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            exported_imports[0],
            exported_imports[1],
            exported_imports[2],
            .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_config.module_name) },
            .{ .name = "cimgui_docking", .module = dep_cimgui.module(cimgui_config.module_name) },
            .{ .name = "build_options", .module = mod_options_module },
        },
    });

    _ = b.addModule("input_plugin", .{
        .root_source_file = b.path("plugins/input/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });

    _ = b.addModule("serialization_plugin", .{
        .root_source_file = b.path("plugins/serialization/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_serialization_imports[0..],
    });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const env_map = std.process.getEnvMap(allocator) catch unreachable;

    if (mod_target.os.tag == .macos) for_darwin: {
        const cups_include_dir = env_map.get("CUPS_INCLUDE_DIR") orelse break :for_darwin;
        const cups_include_path: Build.LazyPath = .{ .cwd_relative = cups_include_dir };
        dep_sokol.artifact("sokol_clib").addIncludePath(cups_include_path);
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
