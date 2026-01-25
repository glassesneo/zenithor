const std = @import("std");
const Build = std.Build;
const log = std.log.scoped(.build);
const sokol = @import("sokol");
const cimgui = @import("cimgui");

// =============================================================================
// PUBLIC API - Plugin Types
// =============================================================================

/// Standard plugins bundled with zenithor.
pub const StandardPlugin = enum {
    renderer,
    gl2d,
    shapes2d,
    shapes3d,
    time,
    imgui,
    input,
    serialization,
    asset,
    sprite,
};

/// Custom plugin module (for user-defined plugins).
pub const PluginModule = struct {
    name: []const u8,
    module: *Build.Module,
};

/// Unified plugin type - either a standard zenithor plugin or a custom module.
pub const Plugin = union(enum) {
    standard: StandardPlugin,
    custom: PluginModule,
};

/// Discoverable namespace for standard plugins.
/// Use with autocomplete: `zenithor.plugins.shapes2d`, `zenithor.plugins.time`, etc.
pub const plugins = struct {
    pub const renderer: Plugin = .{ .standard = .renderer };
    pub const gl2d: Plugin = .{ .standard = .gl2d };
    pub const shapes2d: Plugin = .{ .standard = .shapes2d };
    pub const shapes3d: Plugin = .{ .standard = .shapes3d };
    pub const time: Plugin = .{ .standard = .time };
    pub const imgui: Plugin = .{ .standard = .imgui };
    pub const input: Plugin = .{ .standard = .input };
    pub const serialization: Plugin = .{ .standard = .serialization };
    pub const asset: Plugin = .{ .standard = .asset };
    pub const sprite: Plugin = .{ .standard = .sprite };

    /// Create a custom plugin from a user-defined module.
    pub fn custom(name: []const u8, module: *Build.Module) Plugin {
        return .{ .custom = .{ .name = name, .module = module } };
    }
};

// =============================================================================
// PUBLIC API - Build Options
// =============================================================================

pub const AppOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gl: bool = false,
    gles3: bool = false,
    wgpu: bool = false,
    imgui_docking: bool = false,
    filesystem: bool = false,
    stack_size_mb: u32 = 5,
    /// Plugins to include (standard + custom).
    /// Use `zenithor.plugins.*` for standard plugins.
    plugins: []const Plugin = &.{},
};

// =============================================================================
// INTERNAL - Example Definitions
// =============================================================================

const examples = [_]Example{
    // Minimal app + plugin wiring
    .{ .name = "minimal_app", .plugins = &.{ plugins.shapes2d, plugins.time, plugins.input } },
    // Input + time driven movement
    .{ .name = "input_movement", .plugins = &.{ plugins.renderer, plugins.shapes2d, plugins.time, plugins.input, plugins.imgui } },
    // 2D rendering + layering
    .{ .name = "rendering_2d", .plugins = &.{ plugins.renderer, plugins.shapes2d, plugins.imgui } },
    // 3D scene basics
    .{ .name = "scene_3d", .plugins = &.{ plugins.shapes3d, plugins.time, plugins.input, plugins.imgui } },
    // System staging and ordering
    .{ .name = "system_ordering", .plugins = &.{} },
    // Event flow and error handling
    .{ .name = "error_handling", .plugins = &.{ plugins.renderer, plugins.shapes2d, plugins.time, plugins.imgui } },
    // Serialization round-trip
    .{ .name = "serialization", .plugins = &.{ plugins.renderer, plugins.shapes2d, plugins.time, plugins.input, plugins.imgui, plugins.serialization } },
    // ImGui debug overlay
    .{ .name = "imgui_overlay", .plugins = &.{ plugins.renderer, plugins.shapes3d, plugins.time, plugins.imgui } },
    // Plugin authoring + Requires
    .{ .name = "plugin_authoring", .plugins = &.{ plugins.renderer, plugins.shapes2d, plugins.time, plugins.input, plugins.imgui } },
    // Sprite rendering (replaces asset_loading)
    .{ .name = "sprite_rendering", .plugins = &.{ plugins.renderer, plugins.time, plugins.asset, plugins.sprite, plugins.imgui } },
    // Comprehensive 3D showcase - demonstrates ALL features
    .{ .name = "showcase_3d", .plugins = &.{ plugins.renderer, plugins.shapes3d, plugins.time, plugins.input, plugins.imgui, plugins.serialization } },
    // Custom shader demonstration - rim/Fresnel lighting effect
    .{ .name = "custom_shader_3d", .plugins = &.{ plugins.shapes3d, plugins.time, plugins.input, plugins.imgui } },
};

const Example = struct {
    name: []const u8,
    plugins: []const Plugin,
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
    mod_zenithor: *Build.Module,
};

const DependencySet = struct {
    sokol: *Build.Dependency,
    cimgui: *Build.Dependency,
    sparze: *Build.Dependency,
    renderer_plugin_mod: *Build.Module,
    gl2d_plugin_mod: *Build.Module,
    shapes2d_plugin_mod: *Build.Module,
    shapes3d_plugin_mod: *Build.Module,
    time_plugin_mod: *Build.Module,
    imgui_plugin_mod: *Build.Module,
    input_plugin_mod: *Build.Module,
    serialization_plugin_mod: *Build.Module,
    asset_plugin_mod: *Build.Module,
    sprite_plugin_mod: *Build.Module,
    // Custom shader modules (for custom_shader_3d example)
    rim_shader_mod: *Build.Module,
    rim_spec_mod: *Build.Module,
};

const ExampleResult = struct {
    build: *Build.Step,
    run: *Build.Step.Run,
};

const PluginModules = struct {
    renderer: *Build.Module,
    gl2d: *Build.Module,
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

    // Rim shader (custom shader example)
    const rim_shader_mod = try sokol.shdc.createModule(b, "rim_shader", sokol_mod, .{
        .shdc_dep = dep_shdc,
        .input = "examples/shaders/rim.glsl",
        .output = "rim_shader.zig",
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

    // Renderer plugin - core render pass lifecycle
    const renderer_mod = b.addModule("renderer_plugin", .{
        .root_source_file = b.path("plugins/renderer/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..],
    });

    // GL2D plugin - sokol.gl 2D rendering pipeline
    const gl2d_mod = b.addModule("gl2d_plugin", .{
        .root_source_file = b.path("plugins/gl2d/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "renderer_plugin", .module = renderer_mod },
        },
    });

    // Shapes2D plugin - 2D shape rendering
    const shapes2d_mod = b.addModule("shapes2d_plugin", .{
        .root_source_file = b.path("plugins/shapes2d/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "gl2d_plugin", .module = gl2d_mod },
        },
    });

    // Shapes3D plugin - 3D shape rendering
    const shapes3d_mod = b.addModule("shapes3d_plugin", .{
        .root_source_file = b.path("plugins/shapes3d/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "renderer_plugin", .module = renderer_mod },
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
            .{ .name = "renderer_plugin", .module = renderer_mod },
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
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "renderer_plugin", .module = renderer_mod },
            .{ .name = "time_plugin", .module = time_mod },
        },
    });
    const sprite_mod = b.addModule("sprite_plugin", .{
        .root_source_file = b.path("plugins/sprite/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = exported_imports[0..] ++ &[_]Build.Module.Import{
            .{ .name = "gl2d_plugin", .module = gl2d_mod },
            .{ .name = "asset_plugin", .module = asset_mod },
        },
    });

    // Rim shader spec module (for custom_shader_3d example)
    const rim_spec_mod = b.addModule("rim_spec", .{
        .root_source_file = b.path("examples/shaders/rim.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol_mod },
            .{ .name = "rim_shader", .module = rim_shader_mod },
            .{ .name = "shapes3d_plugin", .module = shapes3d_mod },
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
            .renderer_plugin_mod = renderer_mod,
            .gl2d_plugin_mod = gl2d_mod,
            .shapes2d_plugin_mod = shapes2d_mod,
            .shapes3d_plugin_mod = shapes3d_mod,
            .time_plugin_mod = time_mod,
            .imgui_plugin_mod = imgui_mod,
            .input_plugin_mod = input_mod,
            .serialization_plugin_mod = serialization_mod,
            .asset_plugin_mod = asset_mod,
            .sprite_plugin_mod = sprite_mod,
            .rim_shader_mod = rim_shader_mod,
            .rim_spec_mod = rim_spec_mod,
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

/// Returns the module name for a standard plugin (e.g., .shapes2d -> "shapes2d_plugin").
fn standardPluginName(plugin: StandardPlugin) []const u8 {
    return switch (plugin) {
        .renderer => "renderer_plugin",
        .gl2d => "gl2d_plugin",
        .shapes2d => "shapes2d_plugin",
        .shapes3d => "shapes3d_plugin",
        .time => "time_plugin",
        .imgui => "imgui_plugin",
        .input => "input_plugin",
        .serialization => "serialization_plugin",
        .asset => "asset_plugin",
        .sprite => "sprite_plugin",
    };
}

/// Resolves a standard plugin to its build module.
fn resolveStandardPlugin(lookup: PluginLookup, plugin: StandardPlugin) *Build.Module {
    return switch (lookup) {
        .dependency => |dep| dep.module(standardPluginName(plugin)),
        .modules => |mods| switch (plugin) {
            .renderer => mods.renderer,
            .gl2d => mods.gl2d,
            .shapes2d => mods.shapes2d,
            .shapes3d => mods.shapes3d,
            .time => mods.time,
            .imgui => mods.imgui,
            .input => mods.input,
            .serialization => mods.serialization,
            .asset => mods.asset,
            .sprite => mods.sprite,
        },
    };
}

/// Adds all plugins (standard + custom) to the root module.
fn addPlugins(root_module: *Build.Module, ctx: AppBuildContext, plugins_list: []const Plugin) void {
    for (plugins_list) |plugin| {
        switch (plugin) {
            .standard => |std_plugin| {
                const name = standardPluginName(std_plugin);
                root_module.addImport(name, resolveStandardPlugin(ctx.plugin_lookup, std_plugin));
            },
            .custom => |custom| {
                root_module.addImport(custom.name, custom.module);
            },
        }
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

pub fn buildNative(
    b: *Build,
    dep_zenithor: *Build.Dependency,
    exe: *Build.Step.Compile,
    options: AppOptions,
) void {
    _ = b;
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const ctx = initAppContextFromDependency(dep_zenithor, options, cimgui_config);
    buildNativeWithContext(ctx, exe, options.plugins, cimgui_config);
}

pub fn buildWeb(
    b: *Build,
    dep_zenithor: *Build.Dependency,
    lib: *Build.Step.Compile,
    options: AppOptions,
) !*Build.Step {
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const ctx = initAppContextFromDependency(dep_zenithor, options, cimgui_config);
    return try buildWebWithContext(b, ctx, lib, options, options.plugins, cimgui_config);
}

fn buildNativeExample(b: *Build, example: Example, options: ExampleOptions, deps: DependencySet) ExampleResult {
    const mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
        .target = options.target,
        .optimize = options.optimize,
    });

    // Add rim_spec module for custom_shader_3d example
    if (std.mem.eql(u8, example.name, "custom_shader_3d")) {
        mod.addImport("rim_spec", deps.rim_spec_mod);
    }

    const exe = b.addExecutable(.{
        .name = example.name,
        .root_module = mod,
    });

    const ctx = exampleContext(options, deps);
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    buildNativeWithContext(ctx, exe, example.plugins, cimgui_config);

    if (options.target.result.os.tag == .ios) {
        const allocator = b.allocator;
        const sdk_name = if (options.target.result.abi == .simulator) "iphonesimulator" else "iphoneos";
        const xcrun_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
        }) catch |err| {
            log.warn("Failed to get iOS SDK path: {}", .{err});
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

    // Add rim_spec module for custom_shader_3d example
    if (std.mem.eql(u8, example.name, "custom_shader_3d")) {
        mod.addImport("rim_spec", deps.rim_spec_mod);
    }

    const lib = b.addLibrary(.{
        .name = example.name,
        .root_module = mod,
    });

    const ctx = exampleContext(options, deps);
    const app_options = exampleAppOptions(options);
    const cimgui_config = cimgui.getConfig(options.imgui_docking);
    const link_step = try buildWebWithContext(b, ctx, lib, app_options, example.plugins, cimgui_config);

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

fn buildNativeWithContext(ctx: AppBuildContext, exe: *Build.Step.Compile, plugins_list: []const Plugin, cimgui_config: cimgui.Config) void {
    exe.root_module.addImport("sokol", ctx.dep_sokol.module("sokol"));
    exe.root_module.addImport(cimgui_config.module_name, ctx.dep_cimgui.module(cimgui_config.module_name));
    exe.root_module.addImport("zenithor", ctx.zenithor_mod);
    exe.root_module.addImport("sparze", ctx.dep_sparze.module("sparze"));

    addPlugins(exe.root_module, ctx, plugins_list);
}

fn buildWebWithContext(b: *Build, ctx: AppBuildContext, lib: *Build.Step.Compile, options: AppOptions, plugins_list: []const Plugin, cimgui_config: cimgui.Config) !*Build.Step {
    lib.root_module.addImport("sokol", ctx.dep_sokol.module("sokol"));
    lib.root_module.addImport(cimgui_config.module_name, ctx.dep_cimgui.module(cimgui_config.module_name));
    lib.root_module.addImport("zenithor", ctx.zenithor_mod);
    lib.root_module.addImport("sparze", ctx.dep_sparze.module("sparze"));

    addPlugins(lib.root_module, ctx, plugins_list);

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
            .renderer = deps.renderer_plugin_mod,
            .gl2d = deps.gl2d_plugin_mod,
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
        .mod_zenithor = setup.lib_module,
    }, setup.deps);

    const lib_unit_tests = b.addTest(.{ .root_module = setup.lib_module });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
