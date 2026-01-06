const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const examples = [_]Example{
    // Minimal app + plugin wiring
    .{ .name = "minimal_app", .plugins = &.{ "shapes2d_plugin", "time_plugin", "input_plugin" } },
    // Input + time driven movement
    .{ .name = "input_movement", .plugins = &.{ "render_context_plugin", "shapes2d_plugin", "time_plugin", "input_plugin", "imgui_plugin" } },
    // 2D rendering + layering
    .{ .name = "rendering_2d", .plugins = &.{ "render_context_plugin", "shapes2d_plugin", "imgui_plugin" } },
    // 3D scene basics
    .{ .name = "scene_3d", .plugins = &.{ "shapes3d_plugin", "time_plugin", "input_plugin", "imgui_plugin" } },
    // System staging and ordering
    .{ .name = "system_ordering", .plugins = &.{} },
    // Event flow and error handling
    .{ .name = "error_handling", .plugins = &.{ "render_context_plugin", "shapes2d_plugin", "time_plugin", "imgui_plugin" } },
    // Serialization round-trip
    .{ .name = "serialization", .plugins = &.{ "render_context_plugin", "shapes2d_plugin", "time_plugin", "input_plugin", "imgui_plugin", "serialization_plugin" } },
    // ImGui debug overlay
    .{ .name = "imgui_overlay", .plugins = &.{ "render_context_plugin", "shapes3d_plugin", "time_plugin", "imgui_plugin" } },
    // Plugin authoring + Requires
    .{ .name = "plugin_authoring", .plugins = &.{ "render_context_plugin", "shapes2d_plugin", "time_plugin", "input_plugin", "imgui_plugin" } },
    // Sprite rendering (replaces asset_loading)
    .{ .name = "sprite_rendering", .plugins = &.{ "render_context_plugin", "time_plugin", "asset_plugin", "sprite_plugin", "imgui_plugin" } },
    // Comprehensive 3D showcase - demonstrates ALL features
    .{ .name = "showcase_3d", .plugins = &.{ "render_context_plugin", "shapes3d_plugin", "time_plugin", "input_plugin", "imgui_plugin", "serialization_plugin" } },
};

const Example = struct {
    name: []const u8,
    plugins: []const []const u8,
};

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
    standard_plugins: []const []const u8 = &.{},
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
    standard_plugins: []const []const u8,
    mod_zenithor: *Build.Module,
};

const DependencySet = struct {
    sokol: *Build.Dependency,
    cimgui: *Build.Dependency,
    sparze: *Build.Dependency,
    render_context_plugin_mod: *Build.Module,
    shapes2d_plugin_mod: *Build.Module,
    shapes3d_plugin_mod: *Build.Module,
    time_plugin_mod: *Build.Module,
    imgui_plugin_mod: *Build.Module,
    input_plugin_mod: *Build.Module,
    serialization_plugin_mod: *Build.Module,
    asset_plugin_mod: *Build.Module,
    sprite_plugin_mod: *Build.Module,
};

const ExampleResult = struct {
    build: *Build.Step,
    run: *Build.Step.Run,
};

const PluginModules = struct {
    render_context: *Build.Module,
    shapes2d: *Build.Module,
    shapes3d: *Build.Module,
    time: *Build.Module,
    imgui: *Build.Module,
    input: *Build.Module,
    serialization: *Build.Module,
    asset: *Build.Module,
    sprite: *Build.Module,
};

const PluginLookup = union(enum) {
    dependency: *Build.Dependency,
    modules: PluginModules,
};

const AppBuildContext = struct {
    zenithor_mod: *Build.Module,
    dep_sokol: *Build.Dependency,
    dep_cimgui: *Build.Dependency,
    dep_sparze: *Build.Dependency,
    plugin_lookup: PluginLookup,
};

const BuildFlags = struct {
    gl: bool,
    gles3: bool,
    wgpu: bool,
    imgui_docking: bool,
    filesystem: bool,
    stack_size_mb: u32,
};

const BuildSetup = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    flags: BuildFlags,
    lib_module: *Build.Module,
    deps: DependencySet,
};

fn parseBuildFlags(b: *Build) BuildFlags {
    const stack_size = b.option(u32, "stack-size", "WASM stack size in MB (default: 5, min: 1, max: 16)") orelse 5;
    return .{
        .gl = b.option(bool, "gl", "Whether to use OpenGL backend") orelse false,
        .gles3 = b.option(bool, "gles3", "Whether to use OpenGL ES3 backend") orelse false,
        .wgpu = b.option(bool, "wgpu", "Whether to use WebGPU backend") orelse false,
        .imgui_docking = b.option(bool, "imgui-docking", "Build Dear ImGui with docking support") orelse false,
        .filesystem = b.option(bool, "filesystem", "Enable Emscripten filesystem support (WASM only)") orelse false,
        .stack_size_mb = std.math.clamp(stack_size, 1, 16),
    };
}

fn prepareBuildSetup(b: *Build) !BuildSetup {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const flags = parseBuildFlags(b);
    const cimgui_config = cimgui.getConfig(flags.imgui_docking);

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
        .gl = flags.gl,
        .gles3 = flags.gles3,
        .wgpu = flags.wgpu,
    });
    const sokol_mod = dep_sokol.module("sokol");
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});

    // PBR shader
    const pbr_shader_mod = try sokol.shdc.createModule(b, "pbr_shader", sokol_mod, .{
        .shdc_dep = dep_shdc,
        .input = "plugins/shapes3d/src/shader.glsl",
        .output = "pbr_shader.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl5 = true,
            .metal_macos = true,
            .metal_ios = true,
            .metal_sim = true,
            .wgsl = true,
        },
    });

    // Blinn-Phong shader
    const blinn_phong_shader_mod = try sokol.shdc.createModule(b, "blinn_phong_shader", sokol_mod, .{
        .shdc_dep = dep_shdc,
        .input = "plugins/shapes3d/src/blinn_phong.glsl",
        .output = "blinn_phong_shader.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl5 = true,
            .metal_macos = true,
            .metal_ios = true,
            .metal_sim = true,
            .wgsl = true,
        },
    });

    // Unlit shader
    const unlit_shader_mod = try sokol.shdc.createModule(b, "unlit_shader", sokol_mod, .{
        .shdc_dep = dep_shdc,
        .input = "plugins/shapes3d/src/unlit.glsl",
        .output = "unlit_shader.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl5 = true,
            .metal_macos = true,
            .metal_ios = true,
            .metal_sim = true,
            .wgsl = true,
        },
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

    const lib_module = b.addModule("zenithor", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol_mod },
            .{ .name = cimgui_config.module_name, .module = dep_cimgui.module(cimgui_config.module_name) },
            .{ .name = "sparze", .module = sparze_mod },
        },
    });

    const build_info = b.addOptions();
    build_info.addOption([]const u8, "version", "0.1.0");
    lib_module.addOptions("build_info", build_info);

    const dock_options = b.addOptions();
    dock_options.addOption(bool, "docking", flags.imgui_docking);
    lib_module.addOptions("build_options", dock_options);
    const dock_module = dock_options.createModule();

    const exported_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = lib_module },
        .{ .name = "sokol", .module = sokol_mod },
        .{ .name = "sparze", .module = sparze_mod },
    };
    const exported_serialization_imports = [_]Build.Module.Import{
        .{ .name = "zenithor", .module = lib_module },
        .{ .name = "sparze", .module = sparze_mod },
    };

    // Render context plugin - core render pass lifecycle
    const render_context_mod = b.addModule("render_context_plugin", .{
        .root_source_file = b.path("plugins/render_context/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });

    // Shapes2D plugin - 2D shape rendering
    const shapes2d_mod = b.addModule("shapes2d_plugin", .{
        .root_source_file = b.path("plugins/shapes2d/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "render_context_plugin", .module = render_context_mod },
        },
    });

    // Shapes3D plugin - 3D shape rendering
    const shapes3d_mod = b.addModule("shapes3d_plugin", .{
        .root_source_file = b.path("plugins/shapes3d/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "render_context_plugin", .module = render_context_mod },
            .{ .name = "pbr_shader", .module = pbr_shader_mod },
            .{ .name = "blinn_phong_shader", .module = blinn_phong_shader_mod },
            .{ .name = "unlit_shader", .module = unlit_shader_mod },
        },
    });
    const time_mod = b.addModule("time_plugin", .{
        .root_source_file = b.path("plugins/time/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });
    const imgui_mod = b.addModule("imgui_plugin", .{
        .root_source_file = b.path("plugins/imgui/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            exported_imports[0],
            exported_imports[1],
            exported_imports[2],
            .{ .name = "render_context_plugin", .module = render_context_mod },
            .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_config.module_name) },
            .{ .name = "cimgui_docking", .module = dep_cimgui.module(cimgui_config.module_name) },
            .{ .name = "build_options", .module = dock_module },
        },
    });
    const input_mod = b.addModule("input_plugin", .{
        .root_source_file = b.path("plugins/input/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });
    const serialization_mod = b.addModule("serialization_plugin", .{
        .root_source_file = b.path("plugins/serialization/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_serialization_imports[0..],
    });
    const asset_mod = b.addModule("asset_plugin", .{
        .root_source_file = b.path("plugins/asset/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });
    const sprite_mod = b.addModule("sprite_plugin", .{
        .root_source_file = b.path("plugins/sprite/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "render_context_plugin", .module = render_context_mod },
            .{ .name = "asset_plugin", .module = asset_mod },
        },
    });

    addDarwinIncludePaths(target, dep_sokol);

    return .{
        .target = target,
        .optimize = optimize,
        .flags = flags,
        .lib_module = lib_module,
        .deps = .{
            .sokol = dep_sokol,
            .cimgui = dep_cimgui,
            .sparze = dep_sparze,
            .render_context_plugin_mod = render_context_mod,
            .shapes2d_plugin_mod = shapes2d_mod,
            .shapes3d_plugin_mod = shapes3d_mod,
            .time_plugin_mod = time_mod,
            .imgui_plugin_mod = imgui_mod,
            .input_plugin_mod = input_mod,
            .serialization_plugin_mod = serialization_mod,
            .asset_plugin_mod = asset_mod,
            .sprite_plugin_mod = sprite_mod,
        },
    };
}

fn addDarwinIncludePaths(target: Build.ResolvedTarget, dep_sokol: *Build.Dependency) void {
    if (target.result.os.tag != .macos) return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env_map = std.process.getEnvMap(arena.allocator()) catch unreachable;
    defer env_map.deinit();

    if (env_map.get("CUPS_INCLUDE_DIR")) |cups_dir| {
        const include_path: Build.LazyPath = .{ .cwd_relative = cups_dir };
        dep_sokol.artifact("sokol_clib").addIncludePath(include_path);
    }
}

fn resolvePluginModule(lookup: PluginLookup, name: []const u8) *Build.Module {
    return switch (lookup) {
        .dependency => |dep| dep.module(name),
        .modules => |mods| blk: {
            if (std.mem.eql(u8, name, "render_context_plugin")) break :blk mods.render_context;
            if (std.mem.eql(u8, name, "shapes2d_plugin")) break :blk mods.shapes2d;
            if (std.mem.eql(u8, name, "shapes3d_plugin")) break :blk mods.shapes3d;
            if (std.mem.eql(u8, name, "time_plugin")) break :blk mods.time;
            if (std.mem.eql(u8, name, "imgui_plugin")) break :blk mods.imgui;
            if (std.mem.eql(u8, name, "input_plugin")) break :blk mods.input;
            if (std.mem.eql(u8, name, "serialization_plugin")) break :blk mods.serialization;
            if (std.mem.eql(u8, name, "asset_plugin")) break :blk mods.asset;
            if (std.mem.eql(u8, name, "sprite_plugin")) break :blk mods.sprite;
            std.debug.panic("Unknown plugin name: {s}", .{name});
        },
    };
}

fn addStandardPlugins(root_module: *Build.Module, ctx: AppBuildContext, plugin_names: []const []const u8) void {
    for (plugin_names) |plugin_name| {
        root_module.addImport(plugin_name, resolvePluginModule(ctx.plugin_lookup, plugin_name));
    }
}

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

fn buildExamples(b: *Build, options: ExampleOptions, deps: DependencySet) !void {
    const is_wasm = options.target.result.cpu.arch.isWasm();
    const examples_step = b.step("examples", "Build all examples");

    if (is_wasm) {
        const serve_step = b.step("serve-examples", "Build all examples and serve them");
        const serve_deno = b.addSystemCommand(&.{
            "deno",
            "run",
            "--allow-net",
            "--allow-read",
            "--watch",
            "server/examples.ts",
        });

        for (examples) |example| {
            var example_options = options;
            example_options.standard_plugins = if (example.plugins.len != 0) example.plugins else options.standard_plugins;
            const out = try buildWebExample(b, example, example_options, deps);
            attachExampleSteps(b, example, out, examples_step, &.{ serve_step, &serve_deno.step });
        }

        serve_step.dependOn(&serve_deno.step);
    } else {
        for (examples) |example| {
            var example_options = options;
            example_options.standard_plugins = if (example.plugins.len != 0) example.plugins else options.standard_plugins;
            const out = buildNativeExample(b, example, example_options, deps);
            attachExampleSteps(b, example, out, examples_step, &.{});
        }
    }
}

pub fn buildNative(
    b: *Build,
    dep_zenithor: *Build.Dependency,
    exe: *Build.Step.Compile,
    options: AppOptions,
) void {
    _ = b;
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const ctx = initAppContextFromDependency(dep_zenithor, options, cimgui_config);
    buildNativeWithContext(ctx, exe, options, cimgui_config);
}

pub fn buildWeb(
    b: *Build,
    dep_zenithor: *Build.Dependency,
    lib: *Build.Step.Compile,
    options: AppOptions,
) !*Build.Step {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const ctx = initAppContextFromDependency(dep_zenithor, options, cimgui_config);
    return try buildWebWithContext(b, ctx, lib, options, cimgui_config);
}

fn buildNativeExample(b: *Build, example: Example, options: ExampleOptions, deps: DependencySet) ExampleResult {
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
    });

    const exe = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });

    const ctx = exampleContext(options, deps);
    const app_options = exampleAppOptions(options);
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    buildNativeWithContext(ctx, exe, app_options, cimgui_config);

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
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
    });

    const lib = b.addLibrary(.{
        .name = example.name,
        .root_module = mod,
    });

    const ctx = exampleContext(options, deps);
    const app_options = exampleAppOptions(options);
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const link_step = try buildWebWithContext(b, ctx, lib, app_options, cimgui_config);

    b.getInstallStep().dependOn(link_step);

    const deno = b.addSystemCommand(&.{
        "deno",
        "run",
        "--allow-net",
        "--allow-read",
        "--watch",
        "server/shell.ts",
    });
    deno.addArg(example.name);
    deno.step.dependOn(link_step);

    return .{ .build = link_step, .run = deno };
}

fn initAppContextFromDependency(dep_zenithor: *Build.Dependency, options: AppOptions, cimgui_config: cimgui.Config) AppBuildContext {
    const dep_sokol = dep_zenithor.builder.dependency("sokol", .{
        .target = options.target,
        .optimize = options.optimize,
        .with_sokol_imgui = true,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
    });

    const dep_cimgui = dep_zenithor.builder.dependency("cimgui", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_config.include_dir));

    const dep_sparze = dep_zenithor.builder.dependency("sparze", .{
        .target = options.target,
        .optimize = options.optimize,
    });

    return .{
        .zenithor_mod = dep_zenithor.module("zenithor"),
        .dep_sokol = dep_sokol,
        .dep_cimgui = dep_cimgui,
        .dep_sparze = dep_sparze,
        .plugin_lookup = .{ .dependency = dep_zenithor },
    };
}

fn buildNativeWithContext(ctx: AppBuildContext, exe: *Build.Step.Compile, options: AppOptions, cimgui_config: cimgui.Config) void {
    exe.root_module.addImport("sokol", ctx.dep_sokol.module("sokol"));
    exe.root_module.addImport(cimgui_config.module_name, ctx.dep_cimgui.module(cimgui_config.module_name));
    exe.root_module.addImport("zenithor", ctx.zenithor_mod);
    exe.root_module.addImport("sparze", ctx.dep_sparze.module("sparze"));

    addStandardPlugins(exe.root_module, ctx, options.standard_plugins);

    for (options.plugins) |plugin| {
        exe.root_module.addImport(plugin.name, plugin.module);
    }
}

fn buildWebWithContext(b: *Build, ctx: AppBuildContext, lib: *Build.Step.Compile, options: AppOptions, cimgui_config: cimgui.Config) !*Build.Step {
    lib.root_module.addImport("sokol", ctx.dep_sokol.module("sokol"));
    lib.root_module.addImport(cimgui_config.module_name, ctx.dep_cimgui.module(cimgui_config.module_name));
    lib.root_module.addImport("zenithor", ctx.zenithor_mod);
    lib.root_module.addImport("sparze", ctx.dep_sparze.module("sparze"));

    addStandardPlugins(lib.root_module, ctx, options.standard_plugins);

    for (options.plugins) |plugin| {
        lib.root_module.addImport(plugin.name, plugin.module);
    }

    setupEmscriptenCimgui(ctx.dep_cimgui, ctx.dep_sokol, cimgui_config.clib_name);

    const dep_emsdk = ctx.dep_sokol.builder.dependency("emsdk", .{});
    const stack_arg = b.fmt("-sSTACK_SIZE={d}MB", .{options.stack_size_mb});

    const link = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = options.target,
        .optimize = options.optimize,
        .emsdk = dep_emsdk,
        .use_webgpu = options.wgpu,
        .use_webgl2 = !options.wgpu,
        .use_emmalloc = true,
        .use_filesystem = options.filesystem,
        .shell_file_path = ctx.dep_sokol.path("src/sokol/web/shell.html"),
        .extra_args = if (options.optimize == std.builtin.OptimizeMode.Debug) &.{
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
        } else &.{
            "-sSHARED_MEMORY=0",
            "-sEXIT_RUNTIME=0",
            stack_arg,
            "-sSTACK_OVERFLOW_CHECK=2",
            "-sINITIAL_MEMORY=64MB",
            "-sALLOW_MEMORY_GROWTH=1",
            "-sUSE_PTHREADS=0",
            "--bind",
        },
    });

    return &link.step;
}

fn exampleContext(options: ExampleOptions, deps: DependencySet) AppBuildContext {
    return .{
        .zenithor_mod = options.mod_zenithor,
        .dep_sokol = deps.sokol,
        .dep_cimgui = deps.cimgui,
        .dep_sparze = deps.sparze,
        .plugin_lookup = .{ .modules = .{
            .render_context = deps.render_context_plugin_mod,
            .shapes2d = deps.shapes2d_plugin_mod,
            .shapes3d = deps.shapes3d_plugin_mod,
            .time = deps.time_plugin_mod,
            .imgui = deps.imgui_plugin_mod,
            .input = deps.input_plugin_mod,
            .serialization = deps.serialization_plugin_mod,
            .asset = deps.asset_plugin_mod,
            .sprite = deps.sprite_plugin_mod,
        } },
    };
}

fn exampleAppOptions(options: ExampleOptions) AppOptions {
    return .{
        .target = options.target,
        .optimize = options.optimize,
        .gl = options.gl,
        .gles3 = options.gles3,
        .wgpu = options.wgpu,
        .imgui_docking = options.imgui_docking,
        .filesystem = options.filesystem,
        .stack_size_mb = options.stack_size_mb,
        .standard_plugins = options.standard_plugins,
        .plugins = &.{},
    };
}

pub fn build(b: *Build) !void {
    const setup = try prepareBuildSetup(b);

    const lib = b.addLibrary(.{
        .name = "zenithor",
        .linkage = .static,
        .root_module = setup.lib_module,
    });
    b.installArtifact(lib);

    try buildExamples(b, .{
        .target = setup.target,
        .optimize = setup.optimize,
        .gl = setup.flags.gl,
        .gles3 = setup.flags.gles3,
        .wgpu = setup.flags.wgpu,
        .imgui_docking = setup.flags.imgui_docking,
        .filesystem = setup.flags.filesystem,
        .stack_size_mb = setup.flags.stack_size_mb,
        .standard_plugins = &.{},
        .mod_zenithor = setup.lib_module,
    }, setup.deps);

    const lib_unit_tests = b.addTest(.{ .root_module = setup.lib_module });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
